module grid

  use parametres
  use constantes
  use disk
  use opacity
  use grains
  use em_th
  use prop_star
  use mem
  use utils

  implicit none

  contains

subroutine build_cylindrical_cell_mapping()

  integer :: i,j,k,icell, ntot, ntot2, alloc_status
  integer :: istart,iend,jstart,jend,kstart,kend, istart2,iend2,jstart2,jend2,kstart2,kend2

  istart = 1
  iend = n_rad

  jstart = j_start
  jend = nz

  kstart=1
  kend = n_az

  if (j_start < 0) then
     ntot = (iend - istart + 1) * (jend - jstart) * (kend - kstart + 1)
  else
     ntot = (iend - istart + 1) * (jend - jstart +1) * (kend - kstart + 1)
  endif

  if (ntot /= n_cells) then
     write(*,*) "ERROR in 'build_cylindrical_cell_mapping'"
     write(*,*) "The number of cells is not matching :"
     write(*,*) "ntot=", ntot, "should be", n_cells
     write(*,*) "Exiting."
     stop
  endif

  istart2 = 0
  iend2 = n_rad + 1

  jstart2 = min(1,j_start)-1
  jend2 = nz+1

  kstart2=1
  kend2 = n_az

  if (jstart2 < 0) then
     ntot2 = (iend2 - istart2 + 1) * (jend2 - jstart2) * (kend2 - kstart2 + 1)
  else
     ntot2 = (iend2 - istart2 + 1) * (jend2 - jstart2 +1) * (kend2 - kstart2 + 1)
  endif
  allocate(cell_map(istart2:iend2,jstart2:jend2,kstart2:kend2))
  allocate(cell_map_i(ntot2), cell_map_j(ntot2), cell_map_k(ntot2))

  ! Actual cells
  icell = 0
  do k=kstart, kend
     bz : do j=j_start, jend
        if (j==0) cycle bz
          do i=istart, iend

           icell = icell+1
           if (icell > ntot) then
              write(*,*) "ERROR : there is an issue in the cell mapping"
              write(*,*) "Exiting"
              stop
           endif

           cell_map_i(icell) = i
           cell_map_j(icell) = j
           cell_map_k(icell) = k

           cell_map(i,j,k) = icell
        enddo
     enddo bz
  enddo

  if (icell /= ntot) then
     write(*,*) "Something went wrong in the call mapping"
     write(*,*) "I am missing some real cells"
     write(*,*) icell, ntot
     write(*,*)
     stop
  endif


  ! Virtual cell indices for when the packets are just around the grid

  ! Can the packet exit from this cell : 0 -> no, 1 -> radially, 2 -> vertically
  allocate(lexit_cell(ntot+1:ntot2), stat=alloc_status)
  if (alloc_status > 0) then
     write(*,*) 'Allocation error lexit_cell'
     stop
  endif
  lexit_cell(:) = 0

  ! Cases j=0 and j=nz+1
  do k=kstart, kend
     do j = jstart2, jend2, jend2 - jstart2
        do i=istart2, iend2

           icell = icell+1
           if (icell > ntot2) then
              write(*,*) "ERROR : there is an issue in the cell mapping"
              write(*,*) "Exiting"
              stop
           endif

           if (j==jend2) lexit_cell(icell) = 2

           cell_map_i(icell) = i
           cell_map_j(icell) = j
           cell_map_k(icell) = k

           cell_map(i,j,k) = icell
        enddo
     enddo
  enddo

  ! Cases i=0 and i=n_rad+1 (except j=0 and j=nz+1 done above)
  do k=kstart, kend
     bz2 : do j = jstart, jend
        if (j==0) cycle bz2
        do i=istart2,iend2, iend2-istart2

           icell = icell+1
           if (icell > ntot2) then
              write(*,*) "ERROR : there is an issue in the cell mapping"
              write(*,*) "Extra cells:", icell, ntot2
              write(*,*) i,j,k
              write(*,*) "Exiting"
              stop
           endif

           if (i==iend2) lexit_cell(icell) = 1

           cell_map_i(icell) = i
           cell_map_j(icell) = j
           cell_map_k(icell) = k

           cell_map(i,j,k) = icell
        enddo
     enddo bz2
  enddo

  if (icell /= ntot2) then
     write(*,*) "Something went wrong in the cell mapping"
     write(*,*) "I am missing some virtual cells"
     write(*,*) icell, ntot2
     write(*,*)
     stop
  endif

  !if (cell_map(1,1,1) /= 1) then
  !   write(*,*) "WARNING : mapping of cell (1,1,1) is not 1"
  !   write(*,*) "(1,1,1) --->", cell_map(1,1,1)
  !   write(*,*) "MCFOST might crash"
  !   !write(*,*) "Exiting"
  !   !stop
  !endif

  return

end subroutine build_cylindrical_cell_mapping

!******************************************************************************

pure logical function exit_test_cylindrical(icell, x, y, z)

  integer, intent(in) :: icell
  real(kind=db), intent(in) :: x,y,z

  if (icell <= n_cells) then
     exit_test_cylindrical = .false.
     return
  endif

  if (lexit_cell(icell)==0) then
     exit_test_cylindrical = .false.
  else if (lexit_cell(icell)==1) then ! radial
     exit_test_cylindrical = .true.
  else ! 2 --> vertical
     if (abs(z) > zmaxmax) then
        exit_test_cylindrical = .true.
     else
        exit_test_cylindrical = .false.
     endif
  endif

  return

end function exit_test_cylindrical

!******************************************************************************

!pure subroutine cylindrical2cell(i,j,k, icell)
!
!  integer, intent(in) :: i,j,k
!  integer, intent(out) :: icell
!
!  icell = cell_map(i,j,k)
!
!  return
!
!end subroutine cylindrical2cell

!******************************************************************************

pure subroutine cell2cylindrical(icell, i,j,k)

  integer, intent(in) :: icell
  integer, intent(out) :: i,j,k

  i = cell_map_i(icell)
  j = cell_map_j(icell)
  k = cell_map_k(icell)

  return

end subroutine cell2cylindrical

!******************************************************************************

subroutine cylindrical2cell_old(i,j,k, icell)
  ! icell is between 1 and n_rad * (n_z+1) * n_az

  integer, intent(in) :: i,j,k
  integer, intent(out) :: icell

  if ((i==0).and.(j==0)) then
     icell = 0
  else if (j>nz+1) then
     icell = -i
  else
     icell = i + n_rad * ( j-1 + nz * (k-1))
  endif

  return

end subroutine cylindrical2cell_old

!******************************************************************************

subroutine cell2cylindrical_old(icell, i,j,k)

  integer, intent(in) :: icell
  integer, intent(out) :: i,j,k

  integer :: ij ! indice combine i et j, ie : i + (j-1) * n_rad

  if (icell==0) then
     i=0
     j=0
     k=1
  else if (icell < 0) then
     i = -icell
     j = nz+2
     k = 1
  else
     k = (icell-1)/nrz + 1 ; if (k > n_az) k=n_az

     ij = icell - (k-1)*nrz
     j = (ij-1)/n_rad + 1 ; if (j > nz+1) j=nz+1

     i = ij - (j-1)*n_rad

     !write(*,*) "TEST ij", ij,  ij/n_rad
     !write(*,*) "i,j", i, j
  endif

  return

end subroutine cell2cylindrical_old

!******************************************************************************


subroutine test_convert()

  integer :: i, j, k, icell
  integer :: i2,j2,k2


  write(*,*)
  write(*,*) "TEST CONVERT"

   do k=1, n_az
     do j=1, nz+1
        do i=0, n_rad

           icell = cell_map(i,j,k)
           write(*,*) "convert", i,j,k, "-->", icell

           call cell2cylindrical(icell, i2,j2,k2)
           if (i>0) then
              if ((i/=i2).or.(j/=j2).or.(k2/=k)) then
                 write(*,*) "PB test convert"
                 write(*,*) i,j,k, "-->", icell
                 write(*,*) icell, "-->", i2,j2,k2
                 stop
              endif
           else
              if ((i/=i2)) then ! seul i est defini ds la cas 0
                 write(*,*) "PB test convert"
                 write(*,*) i,j,k, "-->", icell
                 write(*,*) icell, "-->", i2,j2,k2
                 stop
              endif
           endif
        enddo
     enddo
  enddo

  write(*,*) "DONE"
  stop
  return


end subroutine test_convert

!******************************************************************************


 subroutine order_zones()
   ! Order the various zones according to their Rin
   ! C. Pinte
   ! 04/05/11

   integer, dimension(n_zones) :: order
   type(disk_zone_type), dimension(n_zones) :: disk_zone_tmp
   integer, dimension(n_pop) :: Izone_tmp

   integer :: i, ipop

   ! Save arrays to order
   disk_zone_tmp(:) = disk_zone(:)
   Izone_tmp(:) =  dust_pop(:)%zone

   ! order following Rin
   order = bubble_sort(disk_zone(:)%Rmin)

   ! Reordering zones
   do i=1, n_zones
      disk_zone(i) =  disk_zone_tmp(order(i))
      do ipop=1,n_pop  ! reordering zone index in pops
         if (Izone_tmp(ipop) == order(i))  dust_pop(ipop)%zone = i
      enddo
   enddo

   ! Verif
 !  do ipop=1,n_pop
 !     write(*,*) ipop,  dust_pop(ipop)%zone
 !  enddo
 !  stop

   return

 end subroutine order_zones

!******************************************************************************

subroutine define_physical_zones()
  ! Recheche les connections de zone 2 a 2
  ! on doit pouvoir faire mieux que ca
  ! C. Pinte
  ! 03/05/11

  integer :: i, j, index, i_region, iter, ir, k
  logical, dimension(n_zones) :: zone_scanned
  real(kind=db) :: r1, r2, minR, maxR
  character(len=10) :: n1, n2

  logical :: test_j_in_i, test_i_in_j

  ! Detecting connected zones
  zone_scanned(:) = .false.
  index = 0
  do i=1, n_zones
     if (.not.zone_scanned(i)) then
        index = index + 1
        disk_zone(i)%region = index
        zone_scanned(i) = .true.

        ! Current minimum & maximum radii of region
        minR = disk_zone(i)%Rmin
        maxR = disk_zone(i)%Rmax

        ! Besoin d'iterer au cas ou les connections entre zones sont multiples
        ! probablement pas autant mais ca ne coute rien en calcul
        do iter=1, n_zones-1
           do j=i+1, n_zones

              r1 = disk_zone(j)%Rmin
              r2 = disk_zone(j)%Rmax

              ! Test if the 2 zones are imbrigated
              test_j_in_i = ((r1 > minR).and.(r1 < maxR)) .or. ((r2 > minR).and.(r2 <= maxR))
              test_i_in_j = ((minR > r1).and.(minR < r2)) .or. ((maxR > r1).and.(maxR <= r2))

              if ( test_j_in_i .or. test_i_in_j ) then
                 if (.not.zone_scanned(j)) then
                    i_region = index
                 else
                    i_region = disk_zone(j)%region
                 endif ! zone_scanned

                 disk_zone(j)%region = i_region
                 zone_scanned(j) = .true.

                 ! Updating minimum & maximum radii of region
                 minR = min(minR,r1)
                 maxR = max(maxR,r2)
              endif ! test rayon

           enddo ! j
        enddo ! iter
     endif !.not.zone_scanned(i)
  enddo !i

  n_regions = maxval(disk_zone(:)%region)

  allocate(regions(n_regions))
  do ir=1,n_regions
     k = 0
     do i=1, n_zones
        if (disk_zone(i)%region == ir)  k=k+1
     enddo ! i
     regions(ir)%n_zones = k
     allocate(regions(ir)%zones(regions(ir)%n_zones))

     k = 0
     do i=1, n_zones
        if (disk_zone(i)%region == ir)  then
           k=k+1
           regions(ir)%zones(k) = i
        endif
     enddo ! i
  enddo ! ir


  do ir = 1, n_regions
     regions(ir)%Rmin = 1e30
     regions(ir)%Rmax = 0
     do i=1, n_zones
        if (disk_zone(i)%region == ir) then
           regions(ir)%Rmin = min(regions(ir)%Rmin,disk_zone(i)%Rmin)
           regions(ir)%Rmax = max(regions(ir)%Rmax,disk_zone(i)%Rmax)
        endif
     enddo !i
  enddo !ir

  write(*,fmt='(" Number of regions detected:",i2)') n_regions

  do i=1, n_zones
     R1 = real(regions(disk_zone(i)%region)%Rmin)
     R2 = real(regions(disk_zone(i)%region)%Rmax)
     ! Format
     if ((R1 <= 1e-2).or.(R1>=1e6)) then
        n1 = "es8.2"
     else
        n1 = "f"//achar(int(abs(log10(R1))+1)+iachar('3'))//".2"
     endif
     if ((R2 <= 1e-2).or.(R2>=1e6)) then
        n2 = "es8.2"
     else
        n2 = "f"//achar(int(abs(log10(R2))+1)+iachar('3'))//".2"
     endif
     write(*,fmt='(" zone",i2," --> region=",i2," : R=",'//trim(n1)//'," to ",'//trim(n2)//'," AU")') &
          i, disk_zone(i)%region, R1, R2
  enddo

  return

end subroutine define_physical_zones

!******************************************************************************

subroutine define_grid()
  ! Definit la grille du code
  ! Calcule les tableaux zmax, volume, r_lim, r_lim_2, z_lim
  ! et la variable Rmax2
  ! Version 4 gere les subdivisions pour les zones multiples
  ! C. Pinte
  ! 03/05/11, version 3 :  27/04/05

  real, parameter :: pi = 3.1415926535
  real(kind=db) :: rcyl, puiss, rsph, w, uv, p, rcyl_min, rcyl_max, frac
  real :: phi
  integer :: i,j,k, izone, ii, ii_min, ii_max, icell

  !tab en cylindrique ou spherique suivant grille
  real(kind=db), dimension(n_rad) :: V
  real(kind=db), dimension(n_rad+1) :: tab_r, tab_r2, tab_r3
  real(kind=db) ::   r_i, r_f, dr, fac, r0, H, hzone
  real(kind=db) :: delta_r, ln_delta_r, delta_r_in, ln_delta_r_in
  integer :: ir, iz, n_cells_tmp, n_rad_region, n_rad_in_region, n_empty, istart, alloc_status

  type(disk_zone_type) :: dz

  real(kind=db), dimension(:,:), allocatable :: r_grid_tmp, z_grid_tmp
  real(kind=db), dimension(:), allocatable :: phi_grid_tmp

  logical, parameter :: lprint = .false. ! TEMPORARY : the time to validate and test the new routine

  call build_cylindrical_cell_mapping()

  if (l3D) then
     allocate(r_grid_tmp(n_rad,-nz:nz), z_grid_tmp(n_rad,-nz:nz), phi_grid_tmp(n_az), stat=alloc_status)
  else
     allocate(r_grid_tmp(n_rad,nz), z_grid_tmp(n_rad,nz), phi_grid_tmp(n_az), stat=alloc_status)
  endif


  Rmax2 = Rmax*Rmax

  if (grid_type == 1) then
     lcylindrical = .true.
     lspherical = .false.
  else if (grid_type == 2) then
     lcylindrical = .false.
     lspherical = .true.
  else
     write(*,*) "Unknown grid type"
     write(*,*) "Exiting"
     stop
  endif

  n_rad_in = max(n_rad_in,1) ! in case n_rad_in is set to 0 by user

  if (llinear_grid) then

     do i=1, n_rad+1
        tab_r(i) = Rmin + (Rmax - Rmin) * real(i-1)/real(n_rad)
        tab_r2(i) = tab_r(i) * tab_r(i)
        tab_r3(i) = tab_r2(i) * tab_r(i)
     enddo

  else
     ! Definition du nombre de chaques cellules
     n_empty = 3
     n_rad_region = (n_rad - (n_regions -1) * n_empty) / n_regions
     n_rad_in_region = n_rad_in

     n_cells_tmp = 0

     istart = 1
     tab_r(:) = 0.0_db
     do ir=1, n_regions
        if (lprint) then
           write(*,*) "**********************"
           write(*,*) "New region", ir
           write(*,*) "istart", istart, n_rad_in_region, n_rad_in
           write(*,*) "R=", regions(ir)%Rmin, regions(ir)%Rmax
        endif

        regions(ir)%iRmin = istart ; regions(ir)%iRmax = istart+n_rad_region-1 ;

        if (ir == n_regions) then
           n_rad_region = n_rad - n_cells_tmp ! On prend toutes les celles restantes
        endif

        ! Pour eviter d'avoir 2 cellules a la meme position si les regions se touchent
        R0 =  regions(ir)%Rmin
        if (ir > 1) then
           if (regions(ir)%Rmin == regions(ir-1)%Rmax) then
              R0 =  regions(ir)%Rmin * 1.00001_db
           endif
        endif

        ! Grille log avec subdivision cellule interne
        !delta_r = (rout/rmin)**(1.0/(real(n_rad-n_rad_in+1)))
        ln_delta_r = (1.0_db/real(n_rad_region-n_rad_in_region+1,kind=db))*log(regions(ir)%Rmax/R0)
        delta_r = exp(ln_delta_r)

        ln_delta_r_in = (1.0_db/real(n_rad_in_region,kind=db))*log(delta_r)
        delta_r_in = exp(ln_delta_r_in)

        if (lprint) write(*,*) "Delta_r", delta_r, delta_r_in

        ! Selection de la zone correpondante : pente la plus forte
        puiss = 0.0_db
        do iz=1, n_zones
           if (disk_zone(iz)%region == ir) then
              p=1+dz%surf-dz%exp_beta
              if (p > puiss) then
                 puiss = p
              endif
           endif
        enddo

        if (lprint) write(*,*) "n_rad_in, puiss=", puiss

        ! Calcul recursif hors boucle //
        ! Calcul les rayons separant les cellules de (1 a n_rad + 1)

        tab_r(istart) = R0
        tab_r2(istart) = tab_r(istart) * tab_r(istart)
        tab_r3(istart) = tab_r2(istart) * tab_r(istart)

         if (lprint) write(*,*) istart, ir, tab_r(istart)

        if (puiss == 0.0) then
           do i=istart+1, istart + n_rad_in_region
              tab_r(i) = exp(log(R0) - (log(R0)-log(R0*delta_r))*(2.0**(i-istart)-1.0)/(2.0**n_rad_in_region-1.0))
              tab_r2(i) = tab_r(i) * tab_r(i)
              tab_r3(i) = tab_r2(i) * tab_r(i)

              if (lprint) write(*,*) i, ir, tab_r(i)
           enddo
        else
           r_i = exp(puiss*log(R0))
           r_f = exp(puiss*log(R0*delta_r))
           dr=r_f-r_i
           fac = 1.0/(2.0**(n_rad_in_region+1)-1.0)
           do i=istart+1, istart + n_rad_in_region
              tab_r(i) = (R0**puiss - (R0**puiss-(R0*delta_r)**puiss) &
                   *(2.0**(i-istart+1)-1.0)/(2.0**(n_rad_in_region+1)-1.0))**(1.0/puiss)
              !     tab_rcyl(i) = exp( 1.0/puiss * log(r_i + dr * (2.0**(i)-1.0) * fac) )
              !if (tab_rcyl(i) - tab_rcyl(i-1) < 1.0d-15*tab_rcyl(i-1)) then
              if (tab_r(i) - tab_r(i-1) < prec_grille*tab_r(i-1)) then
                 write(*,*) "Error : spatial grid resolution too high"
                 write(*,*) "Differences between two cells are below double precision"
                 stop
              endif
              tab_r2(i) = tab_r(i) * tab_r(i)
              tab_r3(i) = tab_r2(i) * tab_r(i)

              if (lprint) write(*,*) i, ir, tab_r(i)
           enddo
        endif

        if (lprint) write(*,*) "n_rad"

        ! Grille log apres subdivision "1ere" cellule
        do i=istart + n_rad_in_region+1, istart+n_rad_region
           tab_r(i) = tab_r(i-1) * delta_r
           tab_r2(i) = tab_r(i) * tab_r(i)
           tab_r3(i) = tab_r2(i) * tab_r(i)

           if (lprint) write(*,*) i, ir, tab_r(i)
        enddo

        n_cells_tmp = istart+n_rad_region

        ! Cellules vides
        if (ir < n_regions) then
           if ( (regions(ir+1)%Rmin > regions(ir)%Rmax) ) then
              if (lprint) write(*,*) "empty cells"
              ln_delta_r = (1.0_db/real(n_empty+1,kind=db))*log(regions(ir+1)%Rmin/regions(ir)%Rmax)
              delta_r = exp(ln_delta_r)
              do i=istart+n_rad_region+1, istart+n_rad_region+n_empty
                 tab_r(i) = tab_r(i-1) * delta_r
                 tab_r2(i) = tab_r(i) * tab_r(i)
                 tab_r3(i) = tab_r2(i) * tab_r(i)

                 if (lprint) write(*,*) i, ir, tab_r(i)
              enddo
              n_cells_tmp = n_cells_tmp + n_empty
           endif
        endif

        istart = n_cells_tmp+1
     enddo ! ir

  endif ! llinear_grid

  r_lim(0)= rmin
  r_lim_2(0)= rmin**2
  r_lim_3(0) = rmin**3
  do i=1, n_rad
     r_lim(i)=tab_r(i+1)
     r_lim_2(i)= tab_r2(i+1)
     r_lim_3(i)= tab_r3(i+1)
     if (r_lim(i) < r_lim(i-1)) then
        write(*,*) "ERROR in gridding: this is likely to be a bug"
        write(*,*) "i", i, r_lim(i), r_lim(i-1)
        write(*,*) "Exiting"
        stop
     endif
  enddo !i

  if (lcylindrical) then
     ! Calcul volume des cellules (pour calculer leur masse)
     ! On prend ici le rayon au milieu de la cellule
     ! facteur 2 car sym�trie
     ! tab_r est en cylindrique ici

     do i=1, n_rad
        rcyl = 0.5*(r_lim(i) +r_lim(i-1))
        r_grid_tmp(i,:) = rcyl!sqrt(r_lim(i) +r_lim(i-1)))

        ! Estimation du zmax proprement
        ! Recherche de l'echelle de hauteur max des zones pertinentes au rayon donne
        H = 0.
        do izone=1,n_zones
           dz=disk_zone(izone)
           if ((dz%rmin < rcyl).and.(rcyl < dz%Rmax)) then
              hzone = dz%sclht * (rcyl/dz%rref)**dz%exp_beta
              if (hzone > H) H = hzone
           endif ! test rcyl
        enddo ! izone
        zmax(i) = cutoff * H
     enddo ! i

     do i=1, n_rad
        ! Interpolation pour les cellules ou H n'est pas defini (ie entre les zones)
        if (zmax(i) < tiny_real)  then
           search_min: do ii = i-1, 1, -1
              if (zmax(ii) > tiny_real) then
                 ii_min = ii
                 exit search_min
              endif
           enddo search_min !ii

           search_max: do ii = i+1, n_rad
              if (zmax(ii) > tiny_real) then
                 ii_max = ii
                 exit search_max
              endif
           enddo search_max !ii

           ! Interpolation lineaire en log(r)
           rcyl = r_grid_tmp(i,1) ; rcyl_min =  r_grid_tmp(ii_min,1)  ; rcyl_max =  r_grid_tmp(ii_max,1)
           frac = (log(rcyl) - log(rcyl_min)) / (log(rcyl_max) - log(rcyl_min))
           zmax(i) = exp(log(zmax(ii_max)) * frac + log(zmax(ii_min)) * (1.0 - frac))
        endif ! zmax(i) < tiny_real
     enddo !i

     do i=1, n_rad
        if ((tab_r2(i+1)-tab_r2(i)) > 1.0e-6*tab_r2(i)) then
           V(i)=2.0_db*pi*(tab_r2(i+1)-tab_r2(i)) * zmax(i)/real(nz)
           dr2_grid(i) = tab_r2(i+1)-tab_r2(i)
        else
           rcyl = r_grid_tmp(i,1)
           V(i)=4.0_db*pi*rcyl*(tab_r(i+1)-tab_r(i)) * zmax(i)/real(nz)
           dr2_grid(i) = 2.0_db * rcyl*(tab_r(i+1)-tab_r(i))
        endif

        delta_z(i)=zmax(i)/real(nz)
        ! Pas d'integration = moitie + petite dimension cellule
        z_lim(i,nz+1)=zmax(i)

        do j=1,nz
           z_lim(i,j) = (real(j,kind=db)-1.0_db)*delta_z(i)
           z_grid_tmp(i,j) = (real(j,kind=db)-0.5_db)*delta_z(i)
        enddo
     enddo

     z_lim(:,nz+2)=1.0e30
     zmaxmax = maxval(zmax)

  else !lspherical
     izone=1
     dz=disk_zone(izone)


     ! tab_r est en spherique ici
     w_lim(0) = 0.0_db
     theta_lim(0) = 0.0_db
     tan_theta_lim(0) = 1.0e-10_db

     w_lim(nz) = 1.0_db
     theta_lim(nz) = pi/2.
     tan_theta_lim(nz) = 1.e30_db

     do j=1, nz-1
        ! repartition uniforme en cos
        w= real(j,kind=db)/real(nz,kind=db)
        w_lim(j) = w
        tan_theta_lim(j) = w / sqrt(1.0_db - w*w)
        theta_lim(j) = atan(tan_theta_lim(j))
     enddo

     do i=1, n_rad
        !rsph = 0.5*(r_lim(i) +r_lim(i-1))
        rsph = sqrt(r_lim(i) * r_lim(i-1))

        do j=1,nz
           w = (real(j,kind=db)-0.5_db)/real(nz,kind=db)
           uv = sqrt(1.0_db - w*w)
           r_grid_tmp(i,j)=rsph * uv
           z_grid_tmp(i,j)=rsph * w
        enddo

        if (rsph > dz%Rmax) then
           izone = izone +1
           dz=disk_zone(izone)
        endif

        if ((tab_r3(i+1)-tab_r3(i)) > 1.0e-6*tab_r3(i)) then
           V(i)=4.0/3.0*pi*(tab_r3(i+1)-tab_r3(i)) /real(nz)
        else
           V(i)=4.0*pi*rsph**2*(tab_r(i+1)-tab_r(i)) /real(nz)
        endif
     enddo

  endif ! cylindrique ou spherique

  ! Version 3D
  if (l3D) then
     do k=1, n_az
        phi_grid_tmp(k) = 2.0*pi*real(k)/real(n_az)
        phi = phi_grid_tmp(k)
        if (abs(modulo(phi-0.5*pi,pi)) < 1.0e-6) then
           tan_phi_lim(k) = 1.0d300
        else
           tan_phi_lim(k) = tan(phi)
        endif
     enddo !k

     V(:) = V(:) * 0.5 / real(n_az)

     do j=1,nz
        z_grid_tmp(:,-j) = -z_grid_tmp(:,j)
     enddo
  endif

  ! Determine the zone for each cell
  do ir = 1, n_regions
     do i=1, n_rad
        if ((r_grid_tmp(i,1) >  regions(ir)%Rmin).and.(r_grid_tmp(i,1) <  regions(ir)%Rmax)) then
           tab_region(i) = ir
        endif
     enddo
  enddo

  ! Volume and cell arrays with 1D index
  do icell=1, n_cells
     i = cell_map_i(icell)
     j = cell_map_j(icell)
     k = cell_map_k(icell)
     volume(icell) = V(i)

     r_grid(icell) = r_grid_tmp(i,j)
     z_grid(icell) = z_grid_tmp(i,j)
     phi_grid(icell) = phi_grid_tmp(k)
  enddo


  ! Pour Sebastien Charnoz
  if (lSeb_Charnoz) then
     write(*,*) "# n_rad nz"
     write(*,*) n_rad, nz
     write(*,*) "# ir	iz	Rmin		deltaR			Zmin		deltaZ"
     j = 1
     do i=1, n_rad
        do j=1, nz
           write(*,'(I3,3X,I3,3X,ES16.9,3X,ES16.9,3X,ES16.9,3X,ES16.9)') &
                i, j, r_lim(i-1), r_lim(i) - r_lim(i-1), z_lim(i,j),  z_lim(i,j+1) -  z_lim(i,j)
        enddo
     enddo
     stop
  endif ! lSeb_Charnoz

  deallocate(r_grid_tmp,z_grid_tmp,phi_grid_tmp)

  return

end subroutine define_grid

!******************************************************************************

subroutine indice_cellule(xin,yin,zin,ri_out,zj_out)

  implicit none

  real(kind=db), intent(in) :: xin,yin,zin
  integer, intent(out) :: ri_out, zj_out

  real(kind=db) :: r2
  integer :: ri, ri_min, ri_max

  r2 = xin*xin+yin*yin


  if (r2 < r_lim_2(0)) then
     ri_out=0
     zj_out=1
     return
  else if (r2 > Rmax2) then
     ri_out=n_rad
  else
     ri_min=0
     ri_max=n_rad
     ri=(ri_min+ri_max)/2

     do while((ri_max-ri_min) > 1)
        if(r2 > r_lim_2(ri)) then
           ri_min=ri
        else
           ri_max=ri
        endif
        ri=(ri_min+ri_max)/2
     enddo
     ri_out=ri+1
  endif

  zj_out = floor(min(real(abs(zin)/zmax(ri_out) * nz),max_int))+1
  if (zj_out > nz) then
     zj_out = nz + 1
  endif

  return

end subroutine indice_cellule

!******************************************************************************

subroutine indice_cellule_sph(xin,yin,zin,ri_out,thetaj_out)

  implicit none

  real(kind=db), intent(in) :: xin,yin,zin
  integer, intent(out) :: ri_out, thetaj_out

  real(kind=db) :: r2, r02, tan_theta
  integer :: ri, ri_min, ri_max, thetaj, thetaj_min, thetaj_max

  r02 = xin*xin+yin*yin
  r2 = r02+zin*zin

  ! Peut etre un bug en 0, 0 due a la correction sur grid_rmin dans define_grid3
  if (r2 < r_lim_2(0)) then
     ri_out=0
  else if (r2 > Rmax2) then
     ri_out=n_rad
  else
     ri_min=0
     ri_max=n_rad
     ri=(ri_min+ri_max)/2

     do while((ri_max-ri_min) > 1)
        if(r2 > r_lim_2(ri)) then
           ri_min=ri
        else
           ri_max=ri
        endif
        ri=(ri_min+ri_max)/2
     enddo
     ri_out=ri+1
  endif

  ! thetaj_out
  if (r02 > tiny_db) then
     tan_theta = abs(zin) / sqrt(r02)
  else
     tan_theta = 1.0e30
  endif

  thetaj_min = 0
  thetaj_max = nz
  thetaj=(thetaj_min+thetaj_max)/2

  do while((thetaj_max-thetaj_min) > 1)
     if(tan_theta > tan_theta_lim(thetaj)) then
        thetaj_min=thetaj
     else
        thetaj_max=thetaj
     endif
     thetaj=(thetaj_min+thetaj_max)/2
  enddo
  thetaj_out=thetaj+1

  return

end subroutine indice_cellule_sph

!******************************************************************************

subroutine indice_cellule_sph_theta(xin,yin,zin,thetaj_out)

  implicit none

  real(kind=db), intent(in) :: xin,yin,zin
  integer, intent(out) :: thetaj_out

  real(kind=db) :: r02, tan_theta
  integer :: thetaj, thetaj_min, thetaj_max

  r02 = xin*xin+yin*yin

  ! thetaj_out
  if (r02 > tiny_db) then
     tan_theta = abs(zin) / sqrt(r02)
  else
     tan_theta = 1.0e30
  endif

  thetaj_min = 0
  thetaj_max = nz
  thetaj=(thetaj_min+thetaj_max)/2

  do while((thetaj_max-thetaj_min) > 1)
     if(tan_theta > tan_theta_lim(thetaj)) then
        thetaj_min=thetaj
     else
        thetaj_max=thetaj
     endif
     thetaj=(thetaj_min+thetaj_max)/2
  enddo
  thetaj_out=thetaj+1

  return

end subroutine indice_cellule_sph_theta

!******************************************************************************

subroutine indice_cellule_3D(xin,yin,zin,ri_out,zj_out,phik_out)

  implicit none

  real(kind=db), intent(in) :: xin,yin,zin
  integer, intent(out) :: ri_out, zj_out, phik_out

  real(kind=db) :: r2, phi
  integer :: ri, ri_min, ri_max

  r2 = xin*xin+yin*yin

  if (r2 < r_lim_2(0)) then
     ri_out=0
  else if (r2 > Rmax2) then
     ri_out=n_rad
  else
     ri_min=0
     ri_max=n_rad
     ri=(ri_min+ri_max)/2

     do while((ri_max-ri_min) > 1)
        if(r2 > r_lim_2(ri)) then
           ri_min=ri
        else
           ri_max=ri
        endif
        ri=(ri_min+ri_max)/2
     enddo
     ri_out=ri+1
  endif

  if (ri_out > 0) then
     zj_out = floor(min(real(abs(zin)/zmax(ri_out) * nz),max_int))+1
  else
     zj_out = 0
  endif
  if (zj_out > nz) zj_out = nz
  if (zin < 0.0)  zj_out = -zj_out

  if (zin /= 0.0) then
     phi=modulo(atan2(yin,xin),2*real(pi,kind=db))
     phik_out=floor(phi/(2*pi)*real(N_az))+1
     if (phik_out==n_az+1) phik_out=n_az
  else
     phik_out=1
  endif

  return

end subroutine indice_cellule_3D

!******************************************************************************

subroutine indice_cellule_3D_phi(xin,yin,zin,phik_out)

  implicit none

  real(kind=db), intent(in) :: xin,yin,zin
  integer, intent(out) :: phik_out

  real(kind=db) :: phi

  if (zin /= 0.0) then
     phi=modulo(atan2(yin,xin),2*real(pi,kind=db))
     phik_out=floor(phi/(2*pi)*real(N_az))+1
     if (phik_out==n_az+1) phik_out=n_az
  else
     phik_out=1
  endif

  return

end subroutine indice_cellule_3D_phi

!******************************************************************************

subroutine init_lambda()
  ! Initialisation table de longueurs d'onde

  integer :: i

  if (lmono0) then
     ! Lecture longueur d'onde
     read(band,*) tab_lambda(1)
     tab_delta_lambda(1) = 1.0
     tab_lambda_inf(1) = tab_lambda(1)
     tab_lambda_sup(1) = tab_lambda(1)

  else
     ! Initialisation longueurs d'onde
     !delta_lambda = (lambda_max/lambda_min)**(1.0/real(n_lambda))
     delta_lambda =  exp( (1.0_db/real(n_lambda,kind=db)) * log(lambda_max/lambda_min) )

     tab_lambda_inf(1) = lambda_min
     tab_lambda(1)=lambda_min*sqrt(delta_lambda)
     tab_lambda_sup(1) = lambda_min*delta_lambda
     do i=2, n_lambda
        tab_lambda(i)= tab_lambda(i-1)*delta_lambda
        tab_lambda_sup(i)= tab_lambda_sup(i-1)*delta_lambda
        tab_lambda_inf(i)= tab_lambda_sup(i-1)
     enddo

     do i=1, n_lambda
        tab_delta_lambda(i) = tab_lambda_sup(i) - tab_lambda_inf(i)
     enddo

  endif

end subroutine init_lambda

!**********************************************************************

subroutine init_lambda2()
  ! Initialisation table en lambda sed

  implicit none

  integer :: i

  ! reorganisation memoire
  call realloc_step2()

  n_lambda=n_lambda2
  do i=1, n_lambda2
     tab_lambda(i)= tab_lambda2(i)
     tab_lambda_inf(i)= tab_lambda2_inf(i)
     tab_lambda_sup(i)= tab_lambda2_sup(i)
     tab_delta_lambda(i)= tab_delta_lambda2(i)
  enddo

  return

end subroutine init_lambda2

!**********************************************************************

subroutine select_cellule(lambda,aleat,ri,zj, phik)
  ! S�lection de la cellule qui va �mettre le photon
! C. Pinte
! 04/02/05
! Modif 3D 10/06/05

  implicit none

  integer, intent(in) :: lambda
  real, intent(in) :: aleat
  integer, intent(out) :: ri,zj, phik
  integer :: k, kmin, kmax


  ! Dichotomie
  kmin=0
  kmax=n_cells
  k=(kmin+kmax)/2

  do while ((kmax-kmin) > 1)
     if (prob_E_cell(k,lambda) < aleat) then
        kmin = k
     else
        kmax = k
     endif
     k = (kmin + kmax)/2
   enddo   ! while
   k=kmax

   ri = cell_map_i(k)
   zj = cell_map_j(k)
   phik = cell_map_k(k)

   return

end subroutine select_cellule

!**********************************************************************

subroutine pos_em_cellule(ri,zj,phik,aleat1,aleat2,aleat3,x,y,z)
! Choisit la poistion d'emission uniformement dans la cellule
! C. Pinte
! 8/06/07

  implicit none

  integer, intent(in) :: ri, zj, phik
  real, intent(in) :: aleat1, aleat2, aleat3
  real(kind=db), intent(out) :: x,y,z

  if (lspherical) then
     call pos_em_cellule_sph(ri,zj,phik,aleat1,aleat2,aleat3,x,y,z)
  else
     call pos_em_cellule_cyl(ri,zj,phik,aleat1,aleat2,aleat3,x,y,z)
  endif

  return

end subroutine pos_em_cellule

!**********************************************************************

subroutine pos_em_cellule_cyl(ri,zj,phik,aleat1,aleat2,aleat3,x,y,z)
! Choisit la position d'emission uniformement
! dans la cellule (ri,zj)
! Geometrie cylindrique
! C. Pinte
! 04/02/05

  implicit none

  integer, intent(in) :: ri, zj, phik
  real, intent(in) :: aleat1, aleat2, aleat3
  real(kind=db), intent(out) :: x,y,z

  real(kind=db) :: r,phi

  ! Position aleatoire dans cellule
  ! Position radiale
!  r=r_lim(ri-1)+aleat1*(r_lim(ri)-r_lim(ri-1))
!  r=sqrt(r_lim(ri-1)**2+aleat1*(r_lim(ri)**2-r_lim(ri-1)**2))

  ! La premiere cellule ne peut plus etre dans la zone sombre maintenant
 ! if (ri==1) then
 !    r=sqrt(rmin2+aleat1*(r_in_opacite2(zj,phik)-rmin2))
 ! else
     r=sqrt(r_lim_2(ri-1)+aleat1*(r_lim_2(ri)-r_lim_2(ri-1)))
 ! endif
  ! Position verticale
  if (l3D) then ! signe de z = signe de zj
     if (zj > 0) then
        z=z_lim(ri,zj)+aleat2*(z_lim(ri,zj+1)-z_lim(ri,zj))
     else
        z= -(z_lim(ri,-zj)+aleat2*(z_lim(ri,-zj+1)-z_lim(ri,-zj)))
     endif
  else ! 2D : choix al�atoire du signe
     if (aleat2 > 0.5_db) then
        z=z_lim(ri,zj)+(2.0_db*(aleat2-0.5_db))*(z_lim(ri,abs(zj)+1)-z_lim(ri,zj))
     else
        z=-(z_lim(ri,zj)+(2.0_db*aleat2)*(z_lim(ri,zj+1)-z_lim(ri,zj)))
     endif
  endif


  ! Position azimuthale
  !phi=(2.0*aleat3-1.0)*pi
  phi = 2.0_db*pi * (real(phik,kind=db)-1.0_db+aleat3)/real(n_az,kind=db)

  ! x et y
  x=r*cos(phi)
  y=r*sin(phi)

  return

end subroutine pos_em_cellule_cyl

!***********************************************************

subroutine pos_em_cellule_sph(ri,thetaj,phik,aleat1,aleat2,aleat3,x,y,z)
! Choisit la position d'emission uniformement
! dans la cellule (ri,thetaj)
! Geometrie spherique
! C. Pinte
! 08/06/07

  implicit none

  integer, intent(in) :: ri, thetaj, phik
  real, intent(in) :: aleat1, aleat2, aleat3
  real(kind=db), intent(out) :: x,y,z

  real(kind=db) :: r, theta, phi, r_cos_theta

  ! Position radiale
  r=(r_lim_3(ri-1)+aleat1*(r_lim_3(ri)-r_lim_3(ri-1)))**un_tiers

  ! Position theta
  if (aleat2 > 0.5_db) then
     theta=theta_lim(thetaj-1)+(2.0_db*(aleat2-0.5_db))*(theta_lim(thetaj)-theta_lim(thetaj-1))
  else
     theta=-(theta_lim(thetaj-1)+(2.0_db*aleat2)*(theta_lim(thetaj)-theta_lim(thetaj-1)))
  endif

  theta=theta_lim(thetaj-1)+aleat2*(theta_lim(thetaj)-theta_lim(thetaj-1))


  ! BUG ??? : ca doit etre uniforme en w, non ??


  ! Position azimuthale
  phi = 2.0_db*pi * (real(phik)-1.0_db+aleat3)/real(n_az)

  ! x et y
  z=r*sin(theta)
  r_cos_theta = r*cos(theta)
  x=r_cos_theta*cos(phi)
  y=r_cos_theta*sin(phi)



!!$  ! Position theta
!!$  if (aleat2 > 0.5) then
!!$     w=w_lim(thetaj-1)+(2.0_db*(aleat2-0.5_db))*(w_lim(thetaj)-w_lim(thetaj-1))
!!$  else
!!$     w=-(w_lim(thetaj-1)+(2.0_db*aleat2)*(w_lim(thetaj)-w_lim(thetaj-1)))
!!$  endif
!!$
!!$  ! Position azimuthale
!!$  phi = 2.0_db*pi * (real(phik)-1.0_db+aleat3)/real(n_az)
!!$
!!$  ! x et y
!!$  z=r*w
!!$  r_cos_theta = r*sqrt(1.0_db-w*w)
!!$  x=r_cos_theta*cos(phi)
!!$  y=r_cos_theta*sin(phi)

!  z = z_grid(ri,thetaj)
!  r = r_grid(ri,thetaj)
!  x = r*cos(phi)
!  y = r*sin(phi)

 ! call indice_cellule_sph(x,y,z,ri_tmp,thetaj_tmp)
 ! if (ri /= ri_tmp) then
 !    write(*,*) "Bug ri", ri, ri_tmp, sqrt(x*x+y*y)
 !    read(*,*)
 ! else if (thetaj /= thetaj_tmp) then
 !    write(*,*) "Bug zj", w, thetaj, thetaj_tmp
 !    call indice_cellule_sph(x,y,-z,ri_tmp,thetaj_tmp)
 !    write(*,*) -z, thetaj_tmp
 !    read(*,*)
 ! endif


  return

end subroutine pos_em_cellule_sph

!***********************************************************

subroutine angle_disque()

  implicit none

  integer :: i
  logical :: l_1etoile
  real :: r, zr, rmax, zrmax, zzmax

  ! test si le systeme est axisymetrique
  if (n_etoiles > 1) then
     l_1etoile=.false.
  else
     if ((abs(etoile(1)%x) > 1.0e-6).or.(abs(etoile(1)%y) > 1.0e-6).or.(abs(etoile(1)%z) > 1.0e-6))  then
        l_1etoile=.false.
     else
        l_1etoile=.true.
     endif
  endif

  if ((l_sym_axiale).and.(l_1etoile)) then
     ! On cherche le zmax / r le plus grand
     zzmax = zmax(1)
     zrmax = zzmax / rmin
     rmax = rmin
     do i = 1,n_rad
        ! On prend le rayon au bord interne de la cellule
        r= r_lim(i-1)
        zr = zmax(i) / r
        if (zr > zrmax) then
           zrmax = zr
           zzmax = zmax(i)
           rmax = r
        endif
     enddo !i

     ! On calcule la hauteur correspondante a rmin
     cos_max2 = rmax**2/(rmax**2+zzmax**2)

     ! On place le photon juste apres le bord interne (ie dans une cellule non vide)
     r_bord2 = (rmin*1.0001)**2
  else
     cos_max2 = 0.0
  endif

  return

end subroutine angle_disque

end module grid
