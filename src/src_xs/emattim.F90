!
!
!
! Copyright (C) 2006-2008 S. Sagmeister and C. Ambrosch-Draxl.
! This file is distributed under the terms of the GNU General Public License.
! See the file COPYING for license details.
!
Module m_emattim
!
Contains
!
!
      Subroutine emattim (iq, ik, filnam, t1, t2, t3, t4, t5, t6, t7, &
     & t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18)
         Use m_getunit
         Implicit None
    ! arguments
         Integer, Intent (In) :: iq, ik
         Character (*), Intent (In) :: filnam
         Real (8), Intent (In) :: t1, t2, t3, t4, t5, t6, t7, t8, t9, &
        & t10, t11, t12
         Real (8), Intent (In) :: t13, t14, t15, t16, t17 , t18 !, t19, t20, t21
    ! local variables
         Integer :: un
         Real (8) :: tm
         Call getunit (un)
         Open (un, File=trim(filnam), Action='write', Form='formatted', &
        & Position='append')
         tm = t9 + t10 + t11 + t12
         Write (un,*)
         Write (un, '("Timings (CPU seconds) for q-point/k-point : ", 2&
        &i6)') iq, ik
         Write (un, '("  initialisation			   : ", E14.4)') t1
         Write (un, '("  reading APW coefficients		   : ", E14.4)') t2
         Write (un, '("  loop over G(+q) vectors		   : ", E14.4)') t3
         Write (un, '("    summation wrt Gaunt coefficients	   : ", E14&
        &.4)') t6
         Write (un, '("    muffin-tin contribution		   : ", E14.4)') t7
         Write (un, '("      APW-APW				   : ", E14.4)') t14
         Write (un, '("      APW-lo				   : ", E14.4)') t15
         Write (un, '("      lo -APW				   : ", E14.4)') t16
         Write (un, '("      lo -lo				   : ", E14.4)') t17
         Write (un, '("    interstitial contribution		   : ", E14.4)') &
        & t8
         Write (un, '("    matrix multiplications		   : ", E14.4)') tm
         Write (un, '("      APW-lo				   : ", E14.4)') t9
         Write (un, '("      lo -APW				   : ", E14.4)') t10
         Write (un, '("      lo -lo				   : ", E14.4)') t11
         Write (un, '("      interstitial			   : ", E14.4)') t12
         Write (un, '("    FFT   				   : ", E14.4)') t18
         Write (un, '("    debugging				   : ", E14.4)') t13
         Write (un, '("  writing matrix elements to file	   : ", E14.4)&
        &') t4
         Write (un, '("  total				   : ", E14.4)') t5
         Close (un)
      End Subroutine emattim
!
End Module m_emattim
