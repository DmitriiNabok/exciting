module mod_wfutil
  use modmain
  use mod_wannier
  use mod_wfint
  use m_plotmat
  implicit none

! module variables

! methods
  contains
    !BOP
    ! !ROUTINE: wfutil_bandstructure
    ! !INTERFACE:
    !
    subroutine wfutil_bandstructure
      ! !USES:
      use m_getunit 
      use FoX_wxml
      ! !INPUT PARAMETERS:
      ! !DESCRIPTION:
      !   Generates Wannier interpolated bandstructure.
      !
      ! !REVISION HISTORY:
      !   Created November 2017 (SeTi)
      !EOP
      !BOC
      integer :: wf_nvp1d, wf_npp1d, iq, iv, lmax, un, is, ia, ias, ist, l
      real(8) :: sum, emin, emax, dk(3), v(3), m(3,3)
      type( k_set) :: tmp_kset
      type( xmlf_t), save :: xf
      character(256) :: fxt, fname, buffer

      real(8), allocatable :: wf_dvp1d(:), wf_vplp1d(:,:), wf_dpp1d(:), bc(:,:,:,:), velo(:,:,:), mass(:,:,:,:), deriv(:,:,:)

      ! generate k-points along path
      wf_nvp1d = size( input%properties%bandstructure%plot1d%path%pointarray)
      wf_npp1d = input%properties%bandstructure%plot1d%path%steps
      allocate( wf_dvp1d( wf_nvp1d))
      allocate( wf_vplp1d( 3, wf_npp1d))
      allocate( wf_dpp1d( wf_npp1d))
      call connect( bvec, input%properties%bandstructure%plot1d, wf_nvp1d, wf_npp1d, wf_vplp1d, wf_dvp1d, wf_dpp1d)
      call generate_k_vectors( tmp_kset, bvec, (/1, 1, wf_npp1d/), (/0.d0, 0.d0, 0.d0/), .false.)
      !write(*,*) wf_npp1d, tmp_kset%nkpt
      do iq = 1, tmp_kset%nkpt
        tmp_kset%vkl( :, iq) = wf_vplp1d( :, iq)
        call r3mv( bvec, tmp_kset%vkl( :, iq), tmp_kset%vkc( :, iq))
      end do

      ! interpolate energies
      call wfint_init( tmp_kset)
      
      ! interpolate band-derivatives
      if( input%properties%bandstructure%deriv) then
        allocate( deriv( 3, wf_nwf, wfint_kset%nkpt))
        allocate( velo( 3, wf_nwf, wfint_kset%nkpt))
        allocate( mass( 3, 3, wf_nwf, wfint_kset%nkpt))
        call wfint_interpolate_ederiv( velo, mass)
        do ist = 1, wf_nwf
          do iq = 1, wfint_kset%nkpt
            if( iq .eq. 1) then
              dk = wfint_kset%vkc( :, iq+1) - wfint_kset%vkc( :, iq)
            else if( iq .eq. wfint_kset%nkpt) then
              dk = wfint_kset%vkc( :, iq) - wfint_kset%vkc( :, iq-1)
            else
              dk = wfint_kset%vkc( :, iq+1) - wfint_kset%vkc( :, iq-1)
            end if
            dk = dk/norm2( dk)
            call r3mv( mass( :, :, ist, iq), dk, v)
            call r3minv( mass( :, :, ist, iq), m)
            deriv( 1, ist, iq) = dot_product( velo( :, ist, iq), dk)
            deriv( 2, ist, iq) = dot_product( dk, v)
            call r3mv( m, dk, v)
            deriv( 3, ist, iq) = dot_product( dk, v)
          end do
        end do
      end if

      !call wfint_interpolate_eigvec
      !write(*,*) wf_npp1d, tmp_kset%nkpt, wfint_kset%nkpt
      !call wfint_interpolate_gwpermat
      !stop

      ! set Fermi energy to zero in output
      fxt = filext
      if( input%properties%wannier%input .eq. "gw") write( filext, '("_GW.OUT")')
      call readfermi
      filext = fxt
      write( fxt, '(".OUT")')
      if( input%properties%wannier%input .eq. "gw") write( fxt, '("_GW.OUT")')
      if( wf_fermizero) wfint_eval = wfint_eval - efermi
      emin = minval( minval( wfint_eval, 1), 1)
      emax = maxval( maxval( wfint_eval, 1), 1)

      ! generate ouput
      if( input%properties%wannier%input .eq. "gw") then
        call xml_OpenFile( "bandstructure-wannier-gw.xml", xf, replace=.true., pretty_print=.true.)
      else
        call xml_OpenFile( "bandstructure-wannier.xml", xf, replace=.true., pretty_print=.true.)
      end if
      call xml_AddXMLPI( xf, "xml-stylesheet", 'href="'//trim(input%xsltpath)//'/visualizationtemplates/bandstructure2html.xsl" type="text/xsl"')
      call xml_NewElement( xf, "bandstructure")
      
      ! interpolate bandcharacter if requested
      if( input%properties%bandstructure%character) then
        lmax = min( 4, input%groundstate%lmaxapw)
        allocate( bc( 0:lmax, natmtot, wf_nwf, wfint_kset%nkpt))
        call wfint_interpolate_bandchar( lmax, bc)
        
        call xml_AddAttribute( xf, "character", "true")
        call xml_NewElement( xf, "title")
        call xml_AddCharacters( xf, trim(input%title))
        call xml_endElement( xf, "title")
        do is = 1, nspecies
          call xml_NewElement( xf, "species")
          call xml_AddAttribute( xf, "name", trim( spname( is)))
          call xml_AddAttribute( xf, "chemicalSymbol", trim( input%structure%speciesarray( is)%species%chemicalSymbol))
          do ia = 1, natoms( is)
            call xml_NewElement( xf, "atom")
            write( buffer, '(5G18.10)') atposc (:, ia, is)
            call xml_AddAttribute( xf, "coord", trim( adjustl( buffer)))
            ias = idxas( ia, is)
            write( fname, '("BAND_WANNIER_S", I2.2, "_A", I4.4)') is, ia
            call getunit( un)
            open( un, file=trim( fname)//trim( fxt), action='write', form='formatted')

            do ist = 1, wf_nwf
              call xml_NewElement( xf, "band")
              do iq = 1, wfint_kset%nkpt
                sum = 0.d0
                do l = 0, lmax
                  sum = sum + bc( l, ias, ist, iq)
                end do
                call xml_NewElement( xf, "point")
                write( buffer, '(5G18.10)') wf_dpp1d( iq)
                call xml_AddAttribute( xf, "distance", trim( adjustl( buffer)))
                write( buffer, '(5G18.10)') wfint_eval( ist, iq)
                call xml_AddAttribute( xf, "eval", trim( adjustl( buffer)))
                write( buffer, '(5G18.10)') sum
                call xml_AddAttribute( xf, "sum", trim( adjustl( buffer)))
                if( input%properties%bandstructure%deriv) then
                  write( buffer, '(5G18.10)') deriv( 1, ist, iq) 
                  call xml_AddAttribute( xf, "deriv1", trim( adjustl( buffer)))
                  write( buffer, '(5G18.10)') deriv( 2, ist, iq) 
                  call xml_AddAttribute( xf, "deriv2", trim( adjustl( buffer)))
                  write( buffer, '(5G18.10)') deriv( 3, ist, iq) 
                  call xml_AddAttribute( xf, "mass", trim( adjustl( buffer)))
                end if
                do l = 0, lmax
                  call xml_NewElement( xf, "bc")
                  write( buffer, *) l
                  call xml_AddAttribute( xf, "l", trim( adjustl( buffer)))
                  write( buffer, '(5G18.10)') bc( l, ias, ist, iq)
                  call xml_AddAttribute( xf, "character", trim( adjustl( buffer)))
                  call xml_endElement( xf, "bc")
                end do
                call xml_endElement( xf, "point")
                if( input%properties%bandstructure%deriv) then
                  write( un, '(2G18.10, 20F12.6)') wf_dpp1d( iq), wfint_eval( ist, iq), sum, bc( :, ias, ist, iq), deriv( :, ist, iq)
                else
                  write( un, '(2G18.10, 20F12.6)') wf_dpp1d( iq), wfint_eval( ist, iq), sum, bc( :, ias, ist, iq)
                end if
              end do
              call xml_endElement( xf, "band")
              write( un, *)
              !write( un, *)
            end do
            call xml_endElement( xf, "atom")
            close( un)
          end do
          call xml_endElement( xf, "species")
        end do
        write(*,*)
        write(*, '("Info (wfutil_bandstructure):")')
        write(*,*) "band structure plot written to BAND_WANNIER_Sss_Aaaaa"//trim( fxt)
        write(*, '("	for all species and atoms")')
        deallocate( bc)

      ! without bandcharacter
      else
        call getunit( un)
        open( un, file='BAND_WANNIER'//trim( fxt), action='write', form='formatted')
        call xml_NewElement( xf, "title")
        call xml_AddCharacters( xf, trim( input%title))
        call xml_endElement( xf, "title")
        do ist = 1, wf_nwf
          call xml_NewElement( xf, "band")
          do iq = 1, wfint_kset%nkpt
            if( input%properties%bandstructure%deriv) then
              write( un, '(5G18.10)') wf_dpp1d( iq), wfint_eval( ist, iq), deriv( :, ist, iq)
            else
              write( un, '(2G18.10)') wf_dpp1d( iq), wfint_eval( ist, iq)
            end if
            call xml_NewElement( xf, "point")
            write( buffer, '(5G18.10)') wf_dpp1d( iq)
            call xml_AddAttribute( xf, "distance", trim( adjustl( buffer)))
            write( buffer, '(5G18.10)') wfint_eval( ist, iq)
            call xml_AddAttribute (xf, "eval", trim( adjustl( buffer)))
            if( input%properties%bandstructure%deriv) then
              write( buffer, '(5G18.10)') deriv( 1, ist, iq) 
              call xml_AddAttribute( xf, "deriv1", trim( adjustl( buffer)))
              write( buffer, '(5G18.10)') deriv( 2, ist, iq) 
              call xml_AddAttribute( xf, "deriv2", trim( adjustl( buffer)))
              write( buffer, '(5G18.10)') deriv( 3, ist, iq) 
              call xml_AddAttribute( xf, "mass", trim( adjustl( buffer)))
            end if
            call xml_endElement( xf, "point")
          end do
          call xml_endElement( xf, "band")
          write( un, *)
          !write( un, *)
        end do
        close( un)
        write(*,*)
        write(*,'("Info (wfutil_bandstructure):")')
        write(*,*) "band structure plot written to BAND_WANNIER"//trim( fxt)
      end if
      write(*,*)
      if( wf_fermizero) then
        write(*, '(" Fermi energy is at zero in plot")')
      end if

      ! vertex lines
      call getunit( un)
      open( un, file='BANDLINES_WANNIER'//trim( fxt), action='write', form='formatted')
      do iv = 1, wf_nvp1d
        call xml_NewElement( xf, "vertex")
        write( buffer, '(5G18.10)') wf_dvp1d( iv)
        call xml_AddAttribute( xf, "distance", trim( adjustl( buffer)))
        write( buffer, '(5G18.10)') emax
        call xml_AddAttribute( xf, "upperboundary", trim( adjustl( buffer)))
        write( buffer, '(5G18.10)') emin
        call xml_AddAttribute( xf, "lowerboundary", trim( adjustl( buffer)))
        call xml_AddAttribute( xf, "label", trim( adjustl( input%properties%bandstructure%plot1d%path%pointarray( iv)%point%label))) 
        write( buffer, '(5G18.10)') input%properties%bandstructure%plot1d%path%pointarray( iv)%point%coord
        call xml_AddAttribute( xf, "coord", trim( adjustl( buffer)))
        call xml_endElement( xf, "vertex")
        write( un, '(2G18.10)') wf_dvp1d( iv), emin
        write( un, '(2G18.10)') wf_dvp1d( iv), emax
        write( un, *)
      end do
      close( un)
      write(*,*)
      write(*,*) "vertex location lines written to BANDLINES_WANNIER"//trim( fxt)
      write(*,*)
      call xml_endElement( xf, "bandstructure")
      call xml_close( xf)

      ! bandstructure.dat
      call getunit( un)
      if( input%properties%wannier%input .eq. "gw") then
        open( un, file='bandstructure_wannier_gw.dat', action='write', form='formatted')
      else if( input%properties%wannier%input .eq. "qsgw") then
        open( un, file='bandstructure_wannier_qsgw.dat', action='write', form='formatted')
      else
        open( un, file='bandstructure_wannier.dat', action='write', form='formatted')
      end if
      write( un, *) "# ", wf_fst, wf_fst+wf_nwf-1, wfint_kset%nkpt
      do ist = 1, wf_nwf
        do iq = 1, wfint_kset%nkpt
          write( un, '(2I6,3F12.6,2G18.10)') ist+wf_fst-1, iq, wfint_kset%vkl( :, iq), wf_dpp1d( iq), wfint_eval( ist, iq)
        end do
        write( un, *)
      end do
      close( un)

      deallocate( wf_dvp1d, wf_vplp1d, wf_dpp1d)

      return
    end subroutine wfutil_bandstructure

!--------------------------------------------------------------------------------------

    !BOP
    ! !ROUTINE: wfutil_dos
    ! !INTERFACE:
    !
    subroutine wfutil_dos
      ! !USES:
      use m_getunit 
      use FoX_wxml
      ! !INPUT PARAMETERS:
      ! !DESCRIPTION:
      !   Generates Wannier interpolated density of states.
      !
      ! !REVISION HISTORY:
      !   Created November 2017 (SeTi)
      !EOP
      !BOC
      integer :: lmax, lmmax, is, ia, ias, l, m, lm, ie, un, n, ist
      integer :: intgrid(3), nsmooth, neffk, nsube
      real(8) :: ewin(2), scissor
      logical :: genpdos, genjdos
      character(256) :: fname
      character(512) :: buffer
      type (xmlf_t), save :: xf

      real(8), allocatable :: e(:), tdos(:), pdos(:,:,:), jdos(:,:)

      if( minval( input%properties%dos%ngridkint, 1) .le. 0) then
        intgrid = 2*wf_kset%ngridk
        write(*, '(" Warning (wfutil_dos): No or invalid interpolation grid (ngridkint) given: I use twice the original grid.")')
        write(*,'(" given grid: ",3I5)') input%properties%dos%ngridkint
        write(*,'(" used grid:  ",3I5)') intgrid
      else
        intgrid = input%properties%dos%ngridkint
      end if
      
      lmax = min( 3, input%groundstate%lmaxapw)
      lmmax = (lmax+1)**2
      genpdos = input%properties%dos%lmirep
      genjdos = input%properties%dos%jdos
      neffk = input%properties%dos%ngrdos
      nsube = input%properties%dos%nwdos
      nsmooth = input%properties%dos%nsmdos
      scissor = input%properties%dos%scissor
      ewin = input%properties%dos%winddos

      allocate( e( nsube))
      do ie = 1, nsube
        e( ie) = ewin(1) + dble( ie-1)*(ewin(2)-ewin(1))/(nsube-1)
      end do

      allocate( tdos( nsube))
      if( genpdos) allocate( pdos( nsube, lmmax, natmtot))
      if( genjdos) allocate( jdos( nsube, 0:wf_nwf))

      ! interpolate DOS
      if( genpdos .and. .not. genjdos) then
        call wfint_interpolate_dos( lmax, nsmooth, intgrid, neffk, nsube, ewin, tdos, &
             scissor=scissor, &
             pdos=pdos)
      else if( .not. genpdos .and. genjdos) then
        call wfint_interpolate_dos( lmax, nsmooth, intgrid, neffk, nsube, ewin, tdos, &
             scissor=scissor, &
             jdos=jdos, &
             mtrans=m, &
             ntrans=n)
      else if( genpdos .and. genjdos) then
        call wfint_interpolate_dos( lmax, nsmooth, intgrid, neffk, nsube, ewin, tdos, &
             scissor=scissor, &
             pdos=pdos, &
             jdos=jdos, &
             mtrans=m, &
             ntrans=n)
      else
        call wfint_interpolate_dos( lmax, nsmooth, intgrid, neffk, nsube, ewin, tdos, &
             scissor=scissor)
      end if

      ! generate output

      ! total DOS
      call getunit( un)
      open( un, file='TDOS_WANNIER'//trim( filext), action='write', form='formatted')
      call xml_OpenFile( "dos_wannier.xml", xf, replace=.True., pretty_print=.True.)
      call xml_NewElement( xf, "dos")
      call xml_NewElement( xf, "title")
      call xml_AddCharacters( xf, trim(input%title))
      call xml_endElement( xf, "title")
      call xml_NewElement( xf, "axis")
      call xml_AddAttribute( xf, "label", 'Energy')
      call xml_AddAttribute( xf, "unit", 'Hartree')
      call xml_endElement( xf, "axis")
      call xml_NewElement( xf, "axis")
      call xml_AddAttribute( xf, "label", 'DOS')
      call xml_AddAttribute( xf, "unit", 'states/Hartree/unit cell')
      call xml_endElement( xf, "axis")

      call xml_NewElement( xf, "totaldos")
      call xml_NewElement( xf, "diagram")
      call xml_AddAttribute( xf, "type", "totaldos")
      write( buffer,*) 1
      call xml_AddAttribute( xf, "nspin", trim( adjustl( buffer)))

      do ie = 1, nsube
        call xml_NewElement (xf, "point")
        write( buffer, '(G18.10E3)') e( ie)
        call xml_AddAttribute( xf, "e", trim( adjustl( buffer)))
        write( buffer, '(G18.10E3)') occmax*tdos( ie)
        call xml_AddAttribute( xf, "dos", trim( adjustl( buffer)))
        call xml_endElement( xf, "point")
        write( un, '(2G18.10E3)') e( ie), occmax*tdos( ie)
      end do
      write( un, *)
      close( un)
      call xml_endElement( xf, "diagram")
      call xml_endElement( xf, "totaldos")

      ! partial and interstitial DOS
      if( genpdos) then
        do is = 1, nspecies
          do ia = 1, natoms( is)
            ias = idxas( ia, is)
            call getunit( un)
            write( fname, '("PDOS_WANNIER_S",I2.2,"_A",I4.4)') is, ia
            open( un, file=trim( fname)//trim( filext), action='write', form='formatted')
            call xml_NewElement( xf, "partialdos")
            call xml_AddAttribute( xf, "type", "partial")
            call xml_AddAttribute( xf, "speciessym", trim( adjustl( input%structure%speciesarray(is)%species%chemicalSymbol)))
            write( buffer,*) is
            call xml_AddAttribute( xf, "speciesrn", trim( adjustl( buffer)))
            write( buffer,*) ia
            call xml_AddAttribute( xf, "atom", trim( adjustl( buffer)))
            do l = 0, lmax
              if( input%properties%dos%lonly) then
                call xml_NewElement( xf, "diagram")
                write( buffer,*) 1
                call xml_AddAttribute( xf, "nspin", trim( adjustl( buffer)))
                write( buffer,*) l
                call xml_AddAttribute( xf, "l", trim( adjustl( buffer)))
                do ie = 1, nsube
                  call xml_NewElement( xf, "point")
                  write( buffer, '(G18.10E3)') e( ie)
                  call xml_AddAttribute (xf, "e", trim( adjustl( buffer)))
                  write( buffer, '(G18.10E3)') occmax*pdos( ie, l+1, ias)
                  call xml_AddAttribute (xf, "dos", trim( adjustl( buffer)))
                  call xml_endElement( xf, "point")
                  write( un, '(2G18.10E3)') e( ie), occmax*pdos( ie, l+1, ias)
                  tdos( ie) = tdos( ie) - pdos( ie, l+1, ias)
                end do
                write( un, *)
                call xml_endElement( xf, "diagram")
              else
                do m = -l, l
                  lm = idxlm( l, m)
                  call xml_NewElement( xf, "diagram")
                  write( buffer,*) 1
                  call xml_AddAttribute( xf, "nspin", trim( adjustl( buffer)))
                  write( buffer,*) l
                  call xml_AddAttribute( xf, "l", trim( adjustl( buffer)))
                  write( buffer,*) m
                  call xml_AddAttribute( xf, "m", trim( adjustl( buffer)))
                  do ie = 1, nsube
                    call xml_NewElement( xf, "point")
                    write( buffer, '(G18.10E3)') e( ie)
                    call xml_AddAttribute (xf, "e", trim( adjustl( buffer)))
                    write( buffer, '(G18.10E3)') occmax*pdos( ie, lm, ias)
                    call xml_AddAttribute (xf, "dos", trim( adjustl( buffer)))
                    call xml_endElement( xf, "point")
                    write( un, '(2G18.10E3)') e( ie), occmax*pdos( ie, lm, ias)
                    tdos( ie) = tdos( ie) - pdos( ie, lm, ias)
                  end do
                  write( un, *)
                  call xml_endElement( xf, "diagram")
                end do
              end if
            end do
            close( un)
            call xml_endElement( xf, "partialdos")
          end do
        end do
        call getunit( un)
        open( un, file='IDOS_WANNIER'//trim( filext), action='write', form='formatted')
        call xml_NewElement( xf, "interstitialdos")
        call xml_NewElement( xf, "diagram")
        call xml_AddAttribute( xf, "type", "interstitial")
        write( buffer,*) 1
        call xml_AddAttribute( xf, "nspin", trim( adjustl( buffer)))
        do ie = 1, nsube
          call xml_NewElement( xf, "point")
          write( buffer, '(G18.10E3)') e( ie)
          call xml_AddAttribute (xf, "e", trim( adjustl( buffer)))
          write( buffer, '(G18.10E3)') occmax*tdos( ie)
          call xml_AddAttribute (xf, "dos", trim( adjustl( buffer)))
          call xml_endElement( xf, "point")
          write( un, '(2G18.10E3)') e( ie), occmax*tdos( ie)
        end do
        write( un, *)
        close( un)
        call xml_endElement( xf, "diagram")
        call xml_endElement( xf, "interstitialdos")
        deallocate( pdos)
      end if

      ! joint DOS
      if( genjdos) then
        call getunit( un)
        open( un, file='JDOS_WANNIER'//trim( filext), action='write', form='formatted')
        do ist = 1, n
          do ie = 1, nsube
            if( abs( e( ie)) .gt. 1.d-4) then
              write( un, '(3G18.10E3)') e( ie), occmax*jdos( ie, ist)/(e( ie)*e( ie))/dble(m*n), occmax*jdos( ie, ist)
            else
              write( un, '(3G18.10E3)') e( ie), 0.d0, occmax*jdos( ie, ist)
            end if
          end do
          write( un, *)
        end do
        close( un)
        call getunit( un)
        open( un, file='TJDOS_WANNIER'//trim( filext), action='write', form='formatted')
        do ie = 1, nsube
          if( abs( e( ie)) .gt. 1.d-4) then
            write( un, '(3G18.10E3)') e( ie), occmax*jdos( ie, 0)/( e( ie)*e( ie))/dble(m*n), occmax*jdos( ie, 0)
          else
            write( un, '(3G18.10E3)') e( ie), 0.d0, occmax*jdos( ie, 0)
          end if
        end do
        write( un, *)
        close( un)
        deallocate( jdos)
      end if        
              
      deallocate( e, tdos)       

      call xml_endElement( xf, "dos")
      call xml_close( xf)

      write(*,*)
      write(*,*) " Info (wfutil_dos):"
      write(*,*)
      write(*,*) "    Total density of states written to TDOS_WANNIER"//trim( filext)
      write(*,*)
      if( genpdos) then
         write(*,*) "    Partial density of states written to PDOS_Sss_Aaaaa"//trim( filext)
         write(*,*) "    for all species and atoms"
         write(*,*)
         write(*,*) "    Interstitial density of states written to IDOS_WANNIER"//trim( filext)
         write(*,*)
      end if
      if( genjdos) then
         write(*,*) "    Joint density of states written to JDOS_WANNIER"//trim( filext)
         write(*,*)
      end if
      if( wf_fermizero) then
        write(*,*) "    Fermi energy is at zero in plot"
        write(*,*)
      end if
      write(*,*) "    DOS units are states/Hartree/unit cell"
      write(*,*)

      return
    end subroutine wfutil_dos

!--------------------------------------------------------------------------------------
    
    subroutine wfutil_find_bandgap
      use mod_eigenvalue_occupancy, only: occmax
      use mod_charge_and_moment, only: chgval
      use mod_lattice, only: bvec
      use mod_optkgrid, only: getoptkgrid
      use m_getunit

      integer :: iq, nvm, iqvbm, iqcbm, ndiv(3), degvbm, degcbm, ist, n1, un, iv(3)
      real(8) :: vvbm(3), vcbm(3), v0(3), w(3), d(3), m(3,3), evbm, ecbm, eps, rad, opt, ropt
      type( k_set) :: tmp_kset
      logical :: findvbm, findcbm

      real(8), allocatable :: velo(:,:,:), mass(:,:,:,:)

      call getunit( un)

      eps = 1.d-6
      rad = 3.d-2

      findvbm = .true.
      findcbm = .true.

      nvm = nint( chgval/occmax)
      if( (wf_fst .ne. 1) .and. (wf_fst .le. nvm)) then
        write( *, '(" Warning (wfint_find_bandgap): The lowest wannierized band is ",I3,". All bands below are considered to be fully occupied.")') wf_fst
      end if
      if( wf_fst .gt. nvm) then
        write( *, '(" Warning (wfint_find_bandgap): No valence bands have been wannierized. Cannot find VBM.")')
        findvbm = .false.
      end if
      if( (wf_lst .le. nvm)) then
        write( *, '(" Warning (wfint_find_bandgap): No conduction bands have been wannierized. Cannot find CBM.")')
        findcbm = .false.
      end if

      nvm = nvm - wf_fst + 1

      if( minval( input%properties%wanniergap%ngridkint) .gt. 0) then
        ndiv = input%properties%wanniergap%ngridkint
      else
        call getoptkgrid( rad, bvec, ndiv, opt, ropt)
        write( *, '(" Warning (wfint_find_bandgap): No interpolation grid given. I use ",3i4,".")') ndiv
      end if

      w = (/1.d0, 1.d0, 1.d0/)
      if( ndiv(1) .eq. 1) w(1) = 0.d0
      if( ndiv(2) .eq. 1) w(2) = 0.d0
      if( ndiv(3) .eq. 1) w(3) = 0.d0
      d = w/ndiv

      call generate_k_vectors( tmp_kset, bvec, 3*ndiv, (/0.d0, 0.d0, 0.d0/), .true., uselibzint=.true.)
      call wfint_init( tmp_kset)

      if( findvbm .and. findcbm) then
        if( maxval( wfint_eval( nvm, :)) .gt. minval( wfint_eval( nvm+1, :))) then
          write( *, '(" Error (wfint_find_bandgap): I think your system is metalic. No gap can be found.")')
          return
        end if
      end if

      if( findvbm) then
        iqvbm = maxloc( wfint_eval( nvm, :), 1)
        evbm = wfint_eval( nvm, iqvbm)
        vvbm = wfint_kset%vkl( :, iqvbm)
      end if

      if( findcbm) then
        iqcbm = minloc( wfint_eval( nvm+1, :), 1)
        ecbm = wfint_eval( nvm+1, iqcbm)
        vcbm = wfint_kset%vkl( :, iqcbm)
      end if

      ! find VBM
      do while( (norm2( d) .gt. eps) .and. findvbm)
        w = 2.d0*d
        d = w/ndiv
        v0 = vvbm - 0.5d0*(w - d)
        call generate_k_vectors( tmp_kset, bvec, ndiv, (/0.d0, 0.d0, 0.d0/), .false., uselibzint=.true.)
        do iq = 1, tmp_kset%nkpt
          tmp_kset%vkl( :, iq) = tmp_kset%vkl( :, iq)*w + v0
          call r3mv( bvec, tmp_kset%vkl( :, iq), tmp_kset%vkc( :, iq))
        end do
        call wfint_init( tmp_kset)
        iqvbm = maxloc( wfint_eval( nvm, :), 1)
        evbm = wfint_eval( nvm, iqvbm)
        vvbm = wfint_kset%vkl( :, iqvbm)
        call r3ws( input%structure%epslat, bvec, vvbm, iv)
        write(*,'(3f13.6,f23.16)') vvbm, evbm
      end do
        
      ! find CBM
      w = (/1.d0, 1.d0, 1.d0/)
      if( ndiv(1) .eq. 1) w(1) = 0.d0
      if( ndiv(2) .eq. 1) w(2) = 0.d0
      if( ndiv(3) .eq. 1) w(3) = 0.d0
      d = w/ndiv
      do while( (norm2( d) .gt. input%structure%epslat) .and. findcbm)
        w = 2.d0*d
        d = w/ndiv
        v0 = vcbm - 0.5d0*(w - d)
        call generate_k_vectors( tmp_kset, bvec, ndiv, (/0.d0, 0.d0, 0.d0/), .false.)
        do iq = 1, tmp_kset%nkpt
          tmp_kset%vkl( :, iq) = tmp_kset%vkl( :, iq)*w + v0
          call r3mv( bvec, tmp_kset%vkl( :, iq), tmp_kset%vkc( :, iq))
        end do
        call wfint_init( tmp_kset)
        iqcbm = minloc( wfint_eval( nvm+1, :), 1)
        ecbm = wfint_eval( nvm+1, iqvbm)
        vcbm = wfint_kset%vkl( :, iqcbm)
        call r3ws( input%structure%epslat, bvec, vcbm, iv)
        write(*,'(3f13.6,f23.16)') vcbm, ecbm
      end do

      allocate( velo( 3, wf_nwf, wfint_kset%nkpt))
      allocate( mass( 3, 3, wf_nwf, wfint_kset%nkpt))

      open( un, file='GAP_WANNIER.OUT', action='write', form='formatted')

      if( findvbm) then
        call generate_k_vectors( tmp_kset, bvec, (/1, 1, 1/), (/0.d0, 0.d0, 0.d0/), .false.)
        tmp_kset%vkl( :, 1) = vvbm
        call r3mv( bvec, tmp_kset%vkl( :, 1), tmp_kset%vkc( :, 1))
        call wfint_init( tmp_kset)
        call wfint_interpolate_ederiv( velo, mass)
        degvbm = 0
        do ist = 1, wf_nwf
          if( abs( wfint_eval( ist, 1) - wfint_eval( nvm, 1)) .lt. eps) degvbm = degvbm + 1
        end do
        evbm = wfint_eval( nvm, 1)

        write( un, *) "VALENCE-BAND MAXIMUM"
        write( un, '(" position (lattice):      ",3f13.6)') wfint_kset%vkl( :, 1)
        write( un, '("          (cartesian):    ",3f13.6)') wfint_kset%vkc( :, 1)
        write( un, '(" energy (Hartree):        ",f13.6)') evbm
        write( un, '("        (eV):             ",f13.6)') evbm*27.211396641308
        write( un, '(" degeneracy:              ",i6)') degvbm
        do n1 = 1, degvbm
          call r3minv( mass( :, :, nvm-n1+1, 1), m)
          write( un, '(" band gradient ",i2,":        ",3f13.6)') n1, velo( :, nvm-n1+1, 1)
          write( un, '(" effective mass ",i2,":       ",3f13.6)') n1, m( 1, :)
          write( un, '("                          ",3f13.6)') m( 2, :)
          write( un, '("                          ",3f13.6)') m( 3, :)
        end do
        write( un, *)
      end if

      if( findcbm) then
        call generate_k_vectors( tmp_kset, bvec, (/1, 1, 1/), (/0.d0, 0.d0, 0.d0/), .false.)
        tmp_kset%vkl( :, 1) = vcbm
        call r3mv( bvec, tmp_kset%vkl( :, 1), tmp_kset%vkc( :, 1))
        call wfint_init( tmp_kset)
        call wfint_interpolate_ederiv( velo, mass)
        degcbm = 0
        do ist = 1, wf_nwf
          if( abs( wfint_eval( ist, 1) - wfint_eval( nvm+1, 1)) .lt. eps) degcbm = degcbm + 1
        end do
        ecbm = wfint_eval( nvm+1, 1)

        write( un, *) "CONDUCTION-BAND MINIMUM"
        write( un, '(" position (lattice):      ",3f13.6)') wfint_kset%vkl( :, 1)
        write( un, '("          (cartesian):    ",3f13.6)') wfint_kset%vkc( :, 1)
        write( un, '(" energy (Hartree):        ",f13.6)') ecbm
        write( un, '("        (eV):             ",f13.6)') ecbm*27.211396641308
        write( un, '(" degeneracy:              ",i6)') degcbm
        do n1 = 1, degcbm
          call r3minv( mass( :, :, nvm+n1, 1), m)
          write( un, '(" band gradient ",i2,":        ",3f13.6)') n1, velo( :, nvm+n1, 1)
          write( un, '(" effective mass ",i2,":       ",3f13.6)') n1, m( 1, :)
          write( un, '("                          ",3f13.6)') m( 2, :)
          write( un, '("                          ",3f13.6)') m( 3, :)
        end do
        write( un, *)
      end if

      if( findvbm .and. findcbm) then
        write( un, '(" gap (Hartree):           ",f13.6)') ecbm - evbm
        write( un, '("     (eV):                ",f13.6)') (ecbm - evbm)*27.211396641308
      end if

      close( un)

      return
    end subroutine wfutil_find_bandgap


!--------------------------------------------------------------------------------------

end module mod_wfutil
