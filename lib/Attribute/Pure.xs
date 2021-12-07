#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static int ck_pure_sub_eval(pTHX)
{
	int ret = 0;
	
	dJMPENV;

	JMPENV_PUSH(ret);
	if (ret == 0)
		CALLRUNOPS(aTHX);

	JMPENV_POP;
	return ret;
}

//#define REJECT(...) Perl_warn(aTHX_ __VA_ARGS__)
#define REJECT(...)

static OP* ck_pure_sub(pTHX_ OP* entersub, GV* namegv, SV* protosv)
{
//	SV* name = cv_name((SV*)namegv, NULL, 0);
	OP *aop, *cvop, *childop;
	CV* cv;
	U8 want;
	SV* sv;
	SV* const oldwarnhook = PL_warnhook;
	SV* const olddiehook = PL_diehook;
	U8 oldwarn = PL_dowarn;
	OP* ret;

	/* First run the standard checker. */
	if (protosv)
	{
		entersub = ck_entersub_args_proto_or_list(entersub, namegv, protosv);
		if (entersub->op_type != OP_ENTERSUB)
		{
			REJECT("Rejecting inline: opcode was not ENTERSUB after prototype");
			return entersub;
		}
	}

	ret = entersub;
	want = ret->op_flags & OPf_WANT;
	
	aop = cUNOPx(ret)->op_first;
	if (!OpHAS_SIBLING(aop)) aop = aop = cUNOPx(aop)->op_first;
	aop = OpSIBLING(aop);

	for (cvop = aop; OpHAS_SIBLING(cvop); cvop = OpSIBLING(cvop))
	{
		/* cvop points to an argument to this sub, so see if it's a constant and if so get its value and stick it on the stack */
		const OPCODE type = cvop->op_type;

		switch (type)
		{
			case OP_NEXTSTATE:
			case OP_LINESEQ:
			case OP_PUSHMARK:
			case OP_DBSTATE:
			case OP_NULL:
				continue;
			case OP_CONST:
				continue;
			case OP_UNDEF:
				if (cvop->op_flags & OPf_KIDS)
				{
					REJECT("Rejecting inline: UNDEF opcode has a child (e.g. undef $x construct)");
					goto nope;
				}
				continue;
			case OP_RV2AV: /* RV2AV / CONST covers range-constants like 1 .. 5 */
				childop = cUNOPx(cvop)->op_first;
				if (childop->op_type != OP_CONST)
				{
					REJECT("Rejecting inline: RV2AV's child is not a CONST operator (e.g. something other than a list constant)");
					goto nope;
				}
				sv = cSVOPx_sv(childop);
				if (SvAMAGIC(sv))
				{
					REJECT("Rejecting inline: the expected array reference has magic");
					goto nope; // It's magical so reject it.
				}
				/* Ensure it's an array */
				if (SvTYPE(sv) != SVt_PVAV)
				{
					REJECT("Rejecting inline: the constant is not an array");
					goto nope;
				}
				// Otherwise it's a nonmagical array, so we good.
				continue;
			default:
				REJECT("Rejecting inline: unsupported opcode %s", OP_DESC(cvop));
				goto nope;
		}
	}
	
	// We are able to fold this entersub OP.
	// We got called by CHECKOP which means we need to now do the following:
	// op_std_init -> op_integerize -> fold_constants
	// These are static functions in op.c so we have to do it ourselves. On the other hand, we can trim it down to what's relevant to ENTERSUB
	// op_std_init doesn't do anything to ENTERSUB
	// op_integerize doesn't either
	// That leaves fold_constants. Which is basically what we want to do to the *entire* ENTERSUB op.
	OP* curop = LINKLIST(ret);
	OP* old_next = ret->op_next;
	ret->op_next = 0;
	PL_op = curop;

	I32 old_cxix = cxstack_ix;
	Perl_create_eval_scope(aTHX_ NULL, G_FAKINGEVAL);
	
	COP not_compiling;
	StructCopy(&PL_compiling, &not_compiling, COP);
	PL_curcop = &not_compiling;
	PL_warnhook = PERL_WARNHOOK_FATAL;
	PL_diehook = NULL;
	if (!(PL_dowarn & G_WARN_ALL_MASK))
		PL_dowarn |= G_WARN_ON;
	
	// The. Main. Event.
	if (want == OPf_WANT_LIST)
		PUSHMARK(PL_stack_sp);
	int result = ck_pure_sub_eval(aTHX);
	switch (result)
	{
		case 0:
			// Successful execution.
			if (want == OPf_WANT_SCALAR)
			{
				sv = *(PL_stack_sp--);
				if (SvTEMP(sv))
				{
					SvREFCNT_inc_simple_void(sv);
					SvTEMP_off(sv);
				}
				else assert(SvIMMORTAL(sv));
				ret = newSVOP(OP_CONST, 0, MUTABLE_SV(sv));
			}
			else
			{
				// Multiple results: pack it into a list constant
				dSP;
				dMARK;
				dITEMS;
				sv = MUTABLE_SV(av_make(items, MARK+1));
				SP = MARK;
				PUTBACK;
				ret = newUNOP(OP_RV2AV, OPf_PARENS, newSVOP(OP_CONST, 0, sv));
				if (AvFILLp(sv) != 1)
				{
					for (SV** svp = AvARRAY(sv) + AvFILLp(sv); svp >= AvARRAY(sv); --svp)
					{
						SvPADTMP_on(*svp);
						SvREADONLY_on(*svp);
					}
				}
				LINKLIST(ret);
			}
			break;
		case 3:
			ret->op_next = old_next;
			REJECT("Rejecting inline due to error: %" SVf, SVfARG(ERRSV));
			CLEAR_ERRSV();
			break;
		default:
			Perl_croak(aTHX_ "panic: ck_pure_sub JMPENV_PUSH returned %d", result);
	}
	PL_warnhook = oldwarnhook;
	PL_diehook = olddiehook;
	PL_dowarn = oldwarn;
	PL_curcop = &PL_compiling;
	
	if (cxstack_ix > old_cxix)
	{
		Perl_delete_eval_scope(aTHX);
	}

nope:
	if (entersub != ret) op_free(entersub);
	return ret;
}



static OP* ck_pure_sub_scalar(pTHX_ OP* entersub, GV* namegv, SV* protosv)
{
	OP* result = ck_pure_sub(aTHX_ op_contextualize(entersub, G_SCALAR), namegv, protosv);
	
	if (entersub == result)
	{
		// Wrap it inside OP_SCALAR
		return newUNOP(OP_SCALAR, 0, result);
	}
}

static OP* ck_pure_sub_list(pTHX_ OP* entersub, GV* namegv, SV* protosv)
{
	OP* result = ck_pure_sub(aTHX_ op_contextualize(entersub, G_ARRAY), namegv, protosv);
	
	if (entersub == result)
	{
		// Wrap it inside RV2AV > ANONLIST
		OP* al = newLISTOP(OP_ANONLIST, OPf_WANT_LIST, newOP(OP_PUSHMARK,0), result);
		return newUNOP(OP_RV2AV, 0, al);
	}
}

static int setup_callchecker(CV* sub, U8 want)
{

	Perl_call_checker current;
	U32 cflags;
	SV* cobj;

	assert(want == G_SCALAR || want == G_ARRAY);

	if (CvFLAGS(sub) & CVf_LVALUE)
	{
		croak("Cannot apply :Pure/:PureList to an :lvalue sub");
		return 0;
	}

	cv_get_call_checker_flags(sub, 0, &current, &cobj, &cflags);
	if (current == NULL || current == Perl_ck_entersub_args_proto_or_list)
	{
		if (current == NULL) cobj = NULL;
		/* The default checker, so we can go ahead and set ours. */
		cv_set_call_checker_flags(sub,
			(want == G_SCALAR ? ck_pure_sub_scalar : ck_pure_sub_list),
			cobj, CALL_CHECKER_REQUIRE_GV);
		return 1;
	}
	else if (current == ck_pure_sub_scalar && want == G_SCALAR)
	{
		return 0;
	}
	else if (current == ck_pure_sub_list && want == G_ARRAY)
	{
		return 0;
	}
	else if ((current == ck_pure_sub_scalar && want == G_ARRAY) ||
		(current == ck_pure_sub_list && want == G_SCALAR))
	{
		croak("Cannot apply both :Pure and :Purelist to the same sub");
		return 0;
	}
	else
	{
		croak("Cannot assign checker to sub - another checker is already installed");
		return 0;
	}

}

static int is_pure(CV* sub)
{
	Perl_call_checker current;
	U32 cflags;
	SV* cobj;
	cv_get_call_checker_flags(sub, 0, &current, &cobj, &cflags);
	if (current == ck_pure_sub_scalar || current == ck_pure_sub_list)
		return 1;
	return 0;
}

// Why did this have to be a static function?
static OP* next_op(pTHX_ OP* top, OP* o)
{
	OP* sib;
	if ((o->op_flags & OPf_KIDS) && cUNOPo->op_first)
	{
		return cUNOPo->op_first;
	}
	else if ((sib = OpSIBLING(o)))
	{
		return sib;
	}
	else
	{
		OP* parent = o->op_sibparent;
		assert(!(o->op_moresib));
		while (parent && parent != top)
		{
			OP* sib = OpSIBLING(parent);
			if (sib)
				return sib;
			parent = parent->op_sibparent;
		}
		return NULL;
	}
}

MODULE = Attribute::Pure	PACKAGE = Attribute::Pure

int
is_pure(CV* sub) ;

int
contains_impurities(CV* sub)
	PPCODE:
	{
		if (CvISXSUB(sub))
			XSRETURN_NO;
		OP* top = CvROOT(sub);
		for (OP* current = top; current; current = next_op(aTHX_ top, current))
		{
			OP* sib;
			if (current->op_type == OP_ENTERSUB)
			{
				OP* aop = cUNOPx(current)->op_first;
				if (!OpHAS_SIBLING(aop)) aop = cUNOPx(aop)->op_first;
				aop = OpSIBLING(aop);
				while (OpHAS_SIBLING(aop)) aop = OpSIBLING(aop);
				CV* cv = rv2cv_op_cv(aop, 0);
				if (!cv)
				{
					// Note that we also get here if the AMPER flag is set, e.g. &thing
					// Report such calls as 'impurities' regardless.
					if (aop->op_type == OP_NULL && aop->op_targ == OP_RV2CV && cUNOPx(aop)->op_first->op_type == OP_GV)
					{
						OP* svop = cUNOPx(aop)->op_first;
						GV* gv;
#ifdef USE_ITHREADS
						assert(CvDEPTH(cv) >= 1);
						gv = (GV*)(PadARRAY(PadlistARRAY(CvPADLIST(sub))[1])[cPADOPx(svop)->op_padix]);
#else
						gv = (GV*)(cSVOPx(aop)->op_sv);
#endif
						cv = GvCVu(gv);
					}
				}
				if (!cv)
				{
					// No recognizable target pattern, so it's probably not compile-time detectable in the first place.
					continue;
				}
				if (is_pure(cv))
				{
					XSRETURN_YES; // There is no need to go further.
				}
			}
		}
		XSRETURN_NO;
	}

void
_activate_for_sub_scalar(CV* sub)
	PPCODE:
	{
		if (setup_callchecker(sub, G_SCALAR))
			XSRETURN_YES;
		XSRETURN_NO;
	}

void
_activate_for_sub_list(CV* sub)
	PPCODE:
	{
		if (setup_callchecker(sub, G_ARRAY))
			XSRETURN_YES;
		XSRETURN_NO;
	}

	
