module m_ematqk
  use modinput
  use mod_atoms
  use mod_APW_LO
  use mod_muffin_tin
  use mod_constants
  use mod_lattice, only : bvec
  use mod_Gvector, only : ngvec, gc, cfunig, ivg, ivgig
  use mod_Gkvector, only : gkmax, ngkmax
  use m_plotmat
  use modxs, only : fftmap_type

  implicit none
  private

  integer :: nlmomax, lmaxapw, lmaxexp
  real(8) :: emat_gmax
  real(8) :: vecql(3), vecqc(3), vecgc(3)
  integer :: vecgl(3)
  type( fftmap_type) :: fftmap

  integer, allocatable :: nlmo(:), lmo2l(:,:), lmo2m(:,:), lmo2o(:,:), lm2l(:), idxgnt(:,:,:)
  real(8), allocatable :: listgnt(:,:,:)
  complex(8), allocatable :: rigntaa(:,:,:), rigntal(:,:,:), rigntla(:,:,:), rigntll(:,:,:), zfftcf(:)

  public :: emat_init, emat_init_qg, emat_genemat, emat_destroy

! variable

! methods
  contains
      subroutine emat_init( lmaxapw_, lmaxexp_)
          integer, intent( in) :: lmaxapw_, lmaxexp_

          integer :: l1, l2, l3, m1, m2, m3, o1, lm1, lm2, lm3, i, is
          integer :: nlam( lmaxapw_, nspecies), ilo
          real(8) :: gnt, gaunt

          external :: gaunt

          lmaxapw = min( lmaxapw_, input%groundstate%lmaxapw)
          lmaxexp = lmaxexp_
          ! count combined (l,m,o) indices and build index maps
          allocate( nlmo( nspecies))
          allocate( lmo2l( (lmaxapw + 1)**2*apwordmax, nspecies), &
                    lmo2m( (lmaxapw + 1)**2*apwordmax, nspecies), &
                    lmo2o( (lmaxapw + 1)**2*apwordmax, nspecies))
          nlmomax = 0
          do is = 1, nspecies
            nlmo( is) = 0
            do l1 = 0, lmaxapw
              nlam( l1, is) = 0
              do o1 = 1, apword( l1, is)
                nlam( l1, is) = nlam( l1, is)+1
                do m1 = -l1, l1
                  nlmo( is) = nlmo( is) + 1
                  lmo2l( nlmo( is), is) = l1
                  lmo2m( nlmo( is), is) = m1
                  lmo2o( nlmo( is), is) = o1
                end do
              end do
              do ilo = 1, nlorb( is)
                if( lorbl( ilo, is) .eq. l1) nlam( l1, is) = nlam( l1, is) + 1
              end do
              write(*,*) is, l1, nlam( l1, is)
            end do
            nlmomax = max( nlmomax, nlmo( is))
          end do

          allocate( lm2l( (lmaxexp + 1)**2))
          do l1 = 0, lmaxexp
            do m1 = -l1, l1
              lm1 = idxlm( l1, m1)
              lm2l( lm1) = l1
            end do
          end do

          ! build non-zero Gaunt list
          allocate( idxgnt( lmaxapw + 1, (lmaxapw + 1)**2, (lmaxapw + 1)**2), &
                    listgnt( lmaxapw + 1, (lmaxapw + 1)**2, (lmaxapw + 1)**2))
          idxgnt(:,:,:) = 0
          listgnt(:,:,:) = 0.d0
          do l3 = 0, lmaxapw
            do m3 = -l3, l3
              lm3 = idxlm( l3, m3)

              do l1 = 0, lmaxapw
                do m1 = -l1, l1
                  lm1 = idxlm( l1, m1)

                  i = 0
                  do l2 = 0, lmaxexp
                    do m2 = -l2, l2
                      lm2 = idxlm( l2, m2)
                      gnt = gaunt( l1, l2, l3, m1, m2, m3)
                      if( gnt .ne. 0.d0) then
                        i = i + 1
                        listgnt( i, lm1, lm3) = gnt
                        idxgnt( i, lm1, lm3) = lm2
                      end if
                    end do
                  end do

                end do
              end do
            
            end do
          end do

          ! FFT of characteristic function
          emat_gmax = 2*gkmax! +input%xs%gqmax
          call genfftmap( fftmap, emat_gmax)
          allocate( zfftcf( fftmap%ngrtot+1))
          zfftcf = zzero
          do i = 1, ngvec
            if( gc( i) .lt. emat_gmax) then
              zfftcf( fftmap%igfft( i)) = cfunig( i)
            end if
          end do
          call zfftifc( 3, fftmap%ngrid, 1, zfftcf)

          return
      end subroutine emat_init
      
      subroutine emat_init_qg( vecql_, vecgl_)
          real(8), intent( in) :: vecql_(3)
          integer, intent( in) :: vecgl_(3)

          integer :: l1, l2, l3, m1, m2, m3, o1, o2, lm1, lm2, lm3, is, ia, ias, i
          integer :: lmo1, lmo2, ilo1, ilo2, idxlo1, idxlo2, idxlostart
          real(8) :: qgc, tp(2)
          complex(8) :: strf, ylm( (lmaxexp + 1)**2)

          real(8), allocatable :: riaa(:,:,:,:,:), rial(:,:,:,:), rill(:,:,:)

          vecql(:) = vecql_(:)
          vecgl(:) = vecgl_(:)
          call r3mv( bvec, vecql, vecqc)
          call r3mv( bvec, dble( vecgl), vecgc)
          
          ! compute radial integrals times Gaunt and expansion prefactor
          if( allocated( rigntaa)) deallocate( rigntaa)
          allocate( rigntaa( nlmomax, nlmomax, natmtot))
          if( allocated( rigntal)) deallocate( rigntal)
          allocate( rigntal( nlmomax, nlotot, natmtot))
          if( allocated( rigntla)) deallocate( rigntla)
          allocate( rigntla( nlotot, nlmomax, natmtot))
          if( allocated( rigntll)) deallocate( rigntll)
          allocate( rigntll( nlotot, nlotot, natmtot))
          rigntaa(:,:,:) = zzero
          rigntal(:,:,:) = zzero
          rigntla(:,:,:) = zzero
          rigntll(:,:,:) = zzero
          allocate( riaa( 0:lmaxexp, 0:lmaxapw, apwordmax, 0:lmaxapw, apwordmax), &
                    rial( 0:lmaxexp, 0:lmaxapw, apwordmax, nlomax), &
                    rill( 0:lmaxexp, nlomax, nlomax))
          ! generate radial functions
          !call readstate
          call readfermi
          !call linengy
          !call genapwfr
          !call genlofr
          ! multiply radial integral with Gaunt coefficients and expansion prefactor
          idxlostart = 0
          ! generate spherical harmonics
          call sphcrd( vecqc(:) + vecgc(:), qgc, tp)
          call genylm( lmaxexp, tp, ylm)

          do is = 1, nspecies
            do ia = 1, natoms( is)
              ias = idxas( ia, is)
              strf = exp( -zi*dot_product( vecqc(:) + vecgc(:), atposc( :, ia, is)))
              ! generate radial integral
              call emat_genri( is, ia, riaa, rial, rill)
              ! APW-APW
              do lmo2 = 1, nlmo( is)
                l2 = lmo2l( lmo2, is)
                m2 = lmo2m( lmo2, is)
                o2 = lmo2o( lmo2, is)
                lm2 = idxlm( l2, m2)
                do lmo1 = 1, nlmo( is)
                  l1 = lmo2l( lmo1, is)
                  m1 = lmo2m( lmo1, is)
                  o1 = lmo2o( lmo1, is)
                  lm1 = idxlm( l1, m1)
                  i = 1
                  do while( idxgnt( i, lm1, lm2) .ne. 0)
                    lm3 = idxgnt( i, lm1, lm2)
                    l3 = lm2l( lm3)
                    rigntaa( lmo1, lmo2, ias) = rigntaa( lmo1, lmo2, ias) + &
                        strf*conjg( zil( l3))*conjg( ylm( lm3))*listgnt( i, lm1, lm2)*riaa( l3, l1, o1, l2, o2)
                    i = i + 1
                  end do
                  !if( norm2( vecql(:) - (/0.25, 0.25, 0.25/)) .lt. input%structure%epslat) then
                  !  write( *, '(2I3,3x,3I3,3x,3I3,SP,F23.16,F23.16)') is, ia, l1, m1, o1, l2, m2, o2, rigntaa( lmo1, lmo2, ias)/strf
                  !end if
                end do
              end do

              do lmo1 = 1, nlmo( is)
                l1 = lmo2l( lmo1, is)
                m1 = lmo2m( lmo1, is)
                o1 = lmo2o( lmo1, is)
                lm1 = idxlm( l1, m1)
                idxlo1 = 0
                do ilo1 = 1, nlorb( is)
                  l2 = lorbl( ilo1, is)
                  do m2 = -l2, l2
                    lm2 = idxlm( l2, m2)
                    idxlo1 = idxlo1 + 1
                    ! APW-LO
                    i = 1
                    do while( idxgnt( i, lm1, lm2) .ne. 0)
                      lm3 = idxgnt( i, lm1, lm2)
                      l3 = lm2l( lm3)
                      rigntal( lmo1, idxlostart+idxlo1, ias) = rigntal( lmo1, idxlostart+idxlo1, ias) + &
                          strf*conjg( zil( l3))*conjg( ylm( lm3))*listgnt( i, lm1, lm2)*rial( l3, l1, o1, ilo1)
                      i = i + 1
                    end do
                    ! LO-APW
                    i = 1
                    do while( idxgnt( i, lm2, lm1) .ne. 0)
                      lm3 = idxgnt( i, lm2, lm1)
                      l3 = lm2l( lm3)
                      rigntla( idxlostart+idxlo1, lmo1, ias) = rigntla( idxlostart+idxlo1, lmo1, ias) + &
                          strf*conjg( zil( l3))*conjg( ylm( lm3))*listgnt( i, lm2, lm1)*rial( l3, l1, o1, ilo1)
                      i = i + 1
                    end do
                  end do
                end do
              end do

              ! LO-LO
              idxlo2 = 0
              do ilo2 = 1, nlorb( is)
                l2 = lorbl( ilo2, is)
                do m2 = -l2, l2
                  lm2 = idxlm( l2, m2)
                  idxlo2 = idxlo2 + 1
                  idxlo1 = 0
                  do ilo1 = 1, nlorb( is)
                    l1 = lorbl( ilo1, is)
                    do m1 = -l1, l1
                      lm1 = idxlm( l1, m1)
                      idxlo1 = idxlo1 + 1
                      i = 1
                      do while( idxgnt( i, lm1, lm2) .ne. 0)
                        lm3 = idxgnt( i, lm1, lm2)
                        l3 = lm2l( lm3)
                        rigntll( idxlostart+idxlo1, idxlostart+idxlo2, ias) = rigntll( idxlostart+idxlo1, idxlostart+idxlo2, ias) + &
                            strf*conjg( zil( l3))*conjg(ylm( lm3))*listgnt( i, lm1, lm2)*rill( l3, ilo1, ilo2)
                        i = i + 1
                      end do
                    end do
                  end do
                end do
              end do
              
              idxlostart = idxlostart + idxlo2

            end do ! atoms
          end do !species

          deallocate( riaa, rial, rill)
          return
      end subroutine emat_init_qg
      
      subroutine emat_genri( is, ia, riaa, rial, rill)
          integer, intent( in) :: is, ia
          real(8), intent( out) :: riaa( 0:lmaxexp, 0:lmaxapw, apwordmax, 0:lmaxapw, apwordmax)
          real(8), intent( out) :: rial( 0:lmaxexp, 0:lmaxapw, apwordmax, nlomax)
          real(8), intent( out) :: rill( 0:lmaxexp, nlomax, nlomax)

          integer :: ias, ir, nr, l1, l2, l3, o1, o2, ilo1, ilo2
          real(8) :: x, qgc, tp(2)

          real(8), allocatable :: jlqgr(:,:), fr(:), gf(:), cf(:,:)
          
          riaa(:,:,:,:,:) = 0.d0
          rial(:,:,:,:) = 0.d0
          rill(:,:,:) = 0.d0
          
          ias = idxas( ia, is)
          call sphcrd( vecqc(:) + vecgc(:), qgc, tp)
          nr = nrmt( is)
          ! generate spherical Bessel functions
          allocate( jlqgr( 0:lmaxexp, nr))
          do ir = 1, nr
            x = qgc*spr( ir, is)
            call sbessel( lmaxexp, x, jlqgr( :, ir))
          end do

          allocate( fr( nr), gf( nr), cf( 3, nr))
          ! APW-APW
#ifdef USEOMP
!!$OMP PARALLEL DEFAULT(SHARED) PRIVATE( l1, l2, l3, o1, o2, ir, fr, gf, cf)
!!$OMP DO COLLAPSE(5) 
#endif
          do l2 = 0, lmaxapw
            do o2 = 1, apword( l2, is)
              do l1 = 0, lmaxapw
                do o1 = 1, apword( l1, is)
                  do l3 = 0, lmaxexp
                    do ir = 1, nr
                      fr( ir) = apwfr( ir, 1, o1, l1, ias)*jlqgr( l3, ir)*apwfr( ir, 1, o2, l2, ias)*spr( ir, is)**2
                    end do
                    call fderiv( -1, nr, spr( :, is), fr, gf, cf)
                    riaa( l3, l1, o1, l2, o2) = gf( nr)
                  end do
                end do
              end do
            end do
          end do
#ifdef USEOMP
!!$OMP END DO
!!$OMP END PARALLEL
#endif

          ! APW-LO
#ifdef USEOMP
!!$OMP PARALLEL DEFAULT(SHARED) PRIVATE( ilo1, l1, l3, o1, ir, fr, gf, cf)
!!$OMP DO COLLAPSE(4)
#endif
          do ilo1 = 1, nlorb( is)
            do l1 = 0, lmaxapw
              do o1 = 1, apword( l1, is)
                do l3 = 0, lmaxexp
                  do ir = 1, nr
                    fr( ir) = apwfr( ir, 1, o1, l1, ias)*jlqgr( l3, ir)*lofr( ir, 1, ilo1, ias)*spr( ir, is)**2
                  end do
                  call fderiv( -1, nr, spr( :, is), fr, gf, cf)
                  rial( l3, l1, o1, ilo1) = gf( nr)
                end do
              end do
            end do
          end do
#ifdef USEOMP
!!$OMP END DO
!!$OMP END PARALLEL
#endif

          ! LO-LO
#ifdef USEOMP
!!$OMP PARALLEL DEFAULT(SHARED) PRIVATE( ilo1, ilo2, l3, ir, fr, gf, cf)
!!$OMP DO COLLAPSE(3)
#endif
          do ilo2 = 1, nlorb( is)
            do ilo1 = 1, nlorb( is)
              do l3 = 0, lmaxexp
                do ir = 1, nr
                  fr( ir) = lofr( ir, 1, ilo1, ias)*jlqgr( l3, ir)*lofr( ir, 1, ilo2, ias)*spr( ir, is)**2
                end do
                call fderiv( -1, nr, spr( :, is), fr, gf, cf)
                rill( l3, ilo1, ilo2) = gf( nr)
              end do
            end do
          end do
#ifdef USEOMP
!!$OMP END DO
!!$OMP END PARALLEL
#endif

          deallocate( jlqgr, fr, gf, cf)
          return
      end subroutine emat_genri
      
      subroutine emat_genemat( veckl, veckc, fst1, lst1, fst2, lst2, evec1, evec2, emat)
          integer, intent( in) :: fst1, lst1, fst2, lst2
          real(8), intent( in) :: veckl(3), veckc(3)
          complex(8), intent( in) :: evec1( ngkmax+nlotot, fst1:lst1), evec2( ngkmax+nlotot, fst2:lst2)
          complex(8), intent( out) :: emat( fst1:lst1, fst2:lst2)

          integer :: iv(3), ngknr, ngkq, i, is, ia, ias, l, m, o, lmo, lm, nst1, nst2
          integer :: lmolo, ist
          real(8) :: t1, veckql(3), veckqc(3)
          
          integer :: ix, shift(3), ig, ist1, ist2, igs
          complex(8), allocatable :: zfft0(:,:), zfftres(:), zfft(:)

          integer, allocatable :: igkignr(:), igkqig(:) 
          real(8), allocatable :: vecgkql(:,:), vecgkqc(:,:), gkqc(:), tpgkqc(:,:)
          complex(8), allocatable :: sfacgkq(:,:), apwalm1(:,:,:,:), apwalm2(:,:,:,:)
          complex(8), allocatable :: blockmt(:,:), auxmat(:,:), match_combined1(:,:), match_combined2(:,:)
          !complex(8), allocatable :: blockmt(:,:), auxmat(:,:), evecshort1(:,:), evecshort2(:,:)
          !complex(8), allocatable :: aamat(:,:), almat(:,:), lamat(:,:)

          complex(8) :: zdotc
          
          nst1 = lst1-fst1+1
          nst2 = lst2-fst2+2
          emat = zzero

          ! check if q-vector is zero
          t1 = vecql(1)**2 + vecql(2)**2 + vecql(3)**2
          if( t1 .lt. input%structure%epslat) then
            do i = 1, min( lst1-fst1, lst2-fst1)-1
              emat( fst1+i, fst1+i) = zone
            end do
            return
          end if

          allocate( igkignr( ngkmax), igkqig( ngkmax), vecgkql( 3, ngkmax), vecgkqc( 3, ngkmax), gkqc( ngkmax), tpgkqc( 2, ngkmax))
          allocate( sfacgkq( ngkmax, natmtot))
          allocate( apwalm1( ngkmax, apwordmax, lmmaxapw, natmtot))
          allocate( apwalm2( ngkmax, apwordmax, lmmaxapw, natmtot))
          !write( *, '("size of apwalm1: ",5I)') shape( apwalm1), sizeof( apwalm1)
          !write( *, '("size of apwalm2: ",5I)') shape( apwalm2), sizeof( apwalm2)

          ! k+q-vector in lattice coordinates
          veckql = veckl + vecql
          ! map vector components to [0,1) interval
          call r3frac( input%structure%epslat, veckql, iv)
          ! k+q-vector in Cartesian coordinates
          call r3mv( bvec, veckql, veckqc)
          ! generate the G+k+q-vectors
          call gengpvec( veckql, veckqc, ngkq, igkqig, vecgkql, vecgkqc, gkqc, tpgkqc)
          ! generate the structure factors
          call gensfacgp( ngkq, vecgkqc, ngkmax, sfacgkq)
          ! find matching coefficients for k-point k+q
          call match( ngkq, gkqc, tpgkqc, sfacgkq, apwalm2)

          ! generate the G+k-vectors
          call gengpvec( veckl, veckc, ngknr, igkignr, vecgkql, vecgkqc, gkqc, tpgkqc)
          ! generate the structure factors
          call gensfacgp( ngknr, vecgkqc, ngkmax, sfacgkq)
          ! find matching coefficients for k-point k
          call match( ngknr, gkqc, tpgkqc, sfacgkq, apwalm1)
          
          deallocate( vecgkql, vecgkqc, gkqc, tpgkqc, sfacgkq) 
          
          allocate( match_combined1( ngknr, nlmomax), &
                    match_combined2( ngkq, nlmomax))
          !allocate( evecshort1( nlmomax+nlotot, fst1:lst1))
          !allocate( evecshort2( nlmomax+nlotot, fst2:lst2))
          !write( *, '("size of match_combined1: ",4I)') shape( match_combined1), sizeof( match_combined1)
          !write( *, '("size of match_combined2: ",4I)') shape( match_combined2), sizeof( match_combined2)

          ! build block matrix
          ! [_AA_|_AL_]
          ! [ LA | LL ]

          allocate( blockmt( ngknr+nlotot, ngkq+nlotot))
          allocate( auxmat( nlmomax, ngkq))

          !allocate( blockmt( nlmomax+nlotot, nlmomax+nlotot))
          !allocate( auxmat( nlmomax+nlotot, nst2))
          !allocate( auxmat( nst1, nlmomax+nlotot))
          blockmt(:,:) = zzero
          do is = 1, nspecies
            lmolo = nlmo( is)+nlotot
            do ia = 1, natoms( is)
              ias = idxas( ia, is)
              match_combined1 = zzero
              match_combined2 = zzero
              !evecshort1 = zzero
              !evecshort2 = zzero
              do lmo = 1, nlmo( is)
                l = lmo2l( lmo, is)
                m = lmo2m( lmo, is)
                o = lmo2o( lmo, is)
                lm = idxlm( l, m)
                match_combined1( :, lmo) = conjg( apwalm1( 1:ngknr, o, lm, ias))
                match_combined2( :, lmo) = apwalm2( 1:ngkq, o, lm, ias)

                !do ist = fst1, lst1
                !  evecshort1( lmo, ist) = zdotc( ngknr, conjg( evec1( 1:ngknr, ist)), 1, apwalm1( 1:ngknr, o, lm, ias), 1)
                !end do
                !do ist = fst2, lst2
                !  evecshort2( lmo, ist) = zdotc( ngkq, conjg( evec2( 1:ngkq, ist)), 1, apwalm2( 1:ngkq, o, lm, ias), 1)
                !end do
              end do
              !evecshort1( (nlmo( is)+1):lmolo, fst1:lst1) = evec1( (ngknr+1):(ngknr+nlotot), fst1:lst1)
              !evecshort2( (nlmo( is)+1):lmolo, fst2:lst2) = evec2( (ngkq+1):(ngkq+nlotot), fst2:lst2)
              !! sum up block matrix
              !blockmt(:,:) = zzero
              !blockmt( 1:nlmo( is), 1:nlmo( is)) = rigntaa( 1:nlmo( is), 1:nlmo( is), ias)
              !blockmt( 1:nlmo( is), (nlmo( is)+1):lmolo) = rigntal( 1:nlmo( is), :, ias)
              !blockmt( (nlmo( is)+1):lmolo, 1:nlmo( is)) = rigntla( :, 1:nlmo( is), ias)
              !blockmt( (nlmo( is)+1):lmolo, (nlmo( is)+1):lmolo) = rigntll( :, :, ias)
              !
              !call zgemm( 'N', 'N', lmolo, nst2, lmolo, zone, &
              !     blockmt( 1:lmolo, 1:lmolo), lmolo, &
              !     evecshort2( 1:lmolo, fst2:lst2), lmolo, zzero, &
              !     auxmat( 1:lmolo, :), lmolo)
              !call zgemm( 'C', 'N', nst1, nst2, lmolo, cmplx( fourpi, 0.d0, 8), &
              !     evecshort1( 1:lmolo, fst1:lst1), lmolo, &
              !     auxmat( 1:lmolo, :), lmolo, zone, &
              !     emat( fst1:lst1, fst2:lst2), nst1)

              ! APW-APW
              auxmat(:,:) = zzero
              call ZGEMM( 'N', 'T', nlmo( is), ngkq, nlmo( is), zone, &
                   rigntaa( 1:nlmo( is), 1:nlmo( is), ias), nlmo( is), &
                   match_combined2( :, 1:nlmo( is)), ngkq, zzero, &
                   auxmat( 1:nlmo( is), :), nlmo( is))
              call ZGEMM( 'N', 'N', ngknr, ngkq, nlmo( is), zone, &
                   match_combined1( :, 1:nlmo( is)), ngknr, &
                   auxmat( 1:nlmo( is), :), nlmo( is), zone, &
                   blockmt( 1:ngknr, 1:ngkq), ngknr)
              ! APW-LO
              call ZGEMM( 'N', 'N', ngknr, nlotot, nlmo( is), zone, &
                   match_combined1( :, 1:nlmo( is)), ngknr, &
                   rigntal( 1:nlmo( is), :, ias), nlmo( is), zone, &
                   blockmt( 1:ngknr, (ngkq+1):(ngkq+nlotot)), ngknr)
              ! LO-APW
              call ZGEMM( 'N','T', nlotot, ngkq, nlmo( is), zone, &
                   rigntla( :, 1:nlmo( is), ias), nlotot, &
                   match_combined2( :, 1:nlmo( is)), ngkq, zone, &
                   blockmt( (ngknr+1):(ngknr+nlotot), 1:ngkq), nlotot)
              ! LO-LO
              blockmt( (ngknr+1):(ngknr+nlotot), (ngkq+1):(ngkq+nlotot)) = blockmt( (ngknr+1):(ngknr+nlotot), (ngkq+1):(ngkq+nlotot)) + rigntll( :, :, ias)
            end do
          end do
          deallocate( match_combined1, match_combined2, apwalm1, apwalm2, auxmat)
          !deallocate( apwalm1, apwalm2, auxmat, blockmt)

          ! compute final total muffin tin contribution
          allocate( auxmat( ngknr+nlotot, nst2))
          call ZGEMM( 'N', 'N', ngknr+nlotot, nst2, ngkq+nlotot, zone, &
               blockmt(:,:), ngknr+nlotot, &
               evec2( 1:(ngkq+nlotot), fst2:lst2), ngkq+nlotot, zzero, &
               auxmat(:,:), ngknr+nlotot)
          call ZGEMM( 'C', 'N', nst1, nst2, ngknr+nlotot, cmplx( fourpi, 0.d0, 8), &
               evec1( 1:(ngknr+nlotot), fst1:lst1), ngknr+nlotot, &
               auxmat(:,:), ngknr+nlotot, zzero, &
               emat( fst1:lst1, fst2:lst2), nst1)

          deallocate( blockmt, auxmat)
          
          !--------------------------------------!
          !     interstitial matrix elements     !
          !--------------------------------------!
 
          !ikq = ikmapikq (ik, iq)
          veckql = veckl + vecql        !vkql = veckql
                
          ! umklapp treatment
          call r3frac( input%structure%epslat, veckql, shift)
          shift = -shift
          
          allocate( zfft0( fftmap%ngrtot+1, fst1:lst1))
          allocate( zfftres( fftmap%ngrtot+1))
          allocate( zfft( fftmap%ngrtot+1))
          zfft0 = zzero
          
          do ist1 = fst1, lst1
            do ig = 1, ngknr !ngk0 ?
              zfft0( fftmap%igfft( igkignr( ig)), ist1) = evec1( ig, ist1)
            end do
            call zfftifc( 3, fftmap%ngrid, 1, zfft0( :, ist1))
            zfft0( :, ist1) = conjg( zfft0( :, ist1))*zfftcf(:) 
          end do

          do ist2 = fst2, lst2
            zfft = zzero
            if( sum( abs( shift)) .ne. 0) then
              do ig = 1, ngkq !ngkq
                iv = ivg( :, igkqig( ig)) + shift
                igs = ivgig( iv(1), iv(2), iv(3))
                zfft( fftmap%igfft( igs)) = evec2( ig, ist2)
              end do
            else
              do ig = 1, ngkq !ngkq
                zfft( fftmap%igfft( igkqig( ig))) = evec2( ig, ist2)
              end do
            end if
          
            call zfftifc( 3, fftmap%ngrid, 1, zfft)

            do ist1 = fst1, lst1
              do ig = 1, fftmap%ngrtot
                zfftres( ig) = zfft( ig)*zfft0( ig, ist1) 
              end do
          
              call zfftifc( 3, fftmap%ngrid, -1, zfftres)
              emat( ist1, ist2) = emat( ist1, ist2) + zfftres( fftmap%igfft( ivgig( vecgl(1), vecgl(2), vecgl(3))))
            end do
          end do

          deallocate( zfftres, zfft, zfft0, igkignr, igkqig)

          return
      end subroutine emat_genemat

      subroutine emat_destroy
          if( allocated( nlmo)) deallocate( nlmo)
          if( allocated( lmo2l)) deallocate( lmo2l)
          if( allocated( lmo2m)) deallocate( lmo2m)
          if( allocated( lmo2o)) deallocate( lmo2o)
          if( allocated( lm2l)) deallocate( lm2l)
          if( allocated( rigntaa)) deallocate( rigntaa)
          if( allocated( rigntal)) deallocate( rigntal)
          if( allocated( rigntla)) deallocate( rigntla)
          if( allocated( rigntll)) deallocate( rigntll)
          if( allocated( zfftcf)) deallocate( zfftcf)
          if( allocated( idxgnt)) deallocate( idxgnt)
          if( allocated( listgnt)) deallocate( listgnt)
          
          return
      end subroutine emat_destroy
end module m_ematqk
