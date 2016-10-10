module optical_depth

  use parametres
  use disk
  use opacity
  use constantes
  use em_th
  use molecular_emission
  use ray_tracing
  use grains, only : tab_lambda
  use utils
  use molecules

  use dust_ray_tracing
  use grid
  use cylindrical_grid

  implicit none

  contains

subroutine physical_length(id,lambda,p_lambda,Stokes,icell,xio,yio,zio,u,v,w,flag_star,flag_direct_star,extrin,ltot,flag_sortie)
! Integration par calcul de la position de l'interface entre cellules
! Ne met a jour xio, ... que si le photon ne sort pas de la nebuleuse (flag_sortie=1)
! C. Pinte
! 05/02/05

  implicit none

  integer, intent(in) :: id,lambda, p_lambda
  integer, intent(inout) :: icell
  real(kind=db), dimension(4), intent(in) :: Stokes
  logical, intent(in) :: flag_star, flag_direct_star
  real(kind=db), intent(inout) :: u,v,w
  real, intent(in) :: extrin
  real(kind=db), intent(inout) :: xio,yio,zio
  real, intent(out) :: ltot
  logical, intent(out) :: flag_sortie

  real(kind=db) :: x0, y0, z0, x1, y1, z1, x_old, y_old, z_old, extr
  real(kind=db) :: l, tau, opacite
  integer :: icell_in, icell0, icell_old, next_cell, previous_cell

  logical :: lcellule_non_vide, lstop

  lstop = .false.
  flag_sortie = .false.

  x0=xio;y0=yio;z0=zio
  x1=xio;y1=yio;z1=zio

  extr=extrin
  icell_in = icell

  next_cell = icell
  icell0 = 0 ! to define previous_cell

  ltot = 0.0

  ! Calcule les angles de diffusion pour la direction de propagation donnee
  if ((.not.letape_th).and.lscatt_ray_tracing1) call angles_scatt_rt1(id,u,v,w)

  ! Boucle infinie sur les cellules
  do ! Boucle infinie
     ! Indice de la cellule
     icell_old = icell0
     x_old = x0 ; y_old = y0 ; z_old = z0

     x0=x1 ; y0=y1 ; z0=z1
     previous_cell = icell0
     icell0 = next_cell

     ! Test sortie
     if (test_exit_grid(icell0, x0, y0, z0)) then
        flag_sortie = .true.
        return
     endif

     ! Pour cas avec approximation de diffusion
     if (icell0 <= n_cells) then
        lcellule_non_vide=.true.
        opacite=kappa(icell0,lambda)

        if (l_dark_zone(icell0)) then
           ! On renvoie le paquet dans l'autre sens
           u = -u ; v = -v ; w=-w
           ! et on le renvoie au point de depart
           icell = icell_old
           xio = x_old ; yio = y_old ; zio = z_old
           flag_sortie= .false.
           return
        endif
     else
        lcellule_non_vide=.false.
        opacite = 0.0_db
     endif

     ! Calcul longeur de vol et profondeur optique dans la cellule
     call cross_cell(x0,y0,z0, u,v,w,  icell0, previous_cell, x1,y1,z1, next_cell, l)

     ! opacity wall
     !---if (ri0 == 1) then
     !---   ! Variation de hauteur du mur en cos(phi/2)
     !---   phi = atan2(y0,x0)
     !---   hh = h_wall * abs(cos(phi/2.))
     !---   hhm = -h_wall * abs(cos((phi+pi)/2.))
     !---
     !---   ! Ajout de l'opacite du mur le cas echeant
     !---   if ((z0 <= hh).and.(z0 >= hhm)) then
     !---      opacite = opacite + kappa_wall
     !---   endif
     !---endif

     tau = l*opacite ! opacite constante dans la cellule

     ! Comparaison integrale avec tau
     ! et ajustement longueur de vol eventuellement
     if(tau > extr) then ! On a fini d'integrer
        lstop = .true.
        l = l * (extr/tau) ! on rescale l pour que tau=extr
        ltot=ltot+l
     else ! Il reste extr - tau a integrer dans la cellule suivante
        extr=extr-tau
        ltot=ltot+l
     endif

     ! Stockage des champs de radiation
     if (lcellule_non_vide) call save_radiation_field(id,lambda,p_lambda, icell0, Stokes, l, &
          x0,y0,z0, x1,y1,z1, u,v,w, flag_star, flag_direct_star)

     ! On a fini d'integrer : sortie de la routine
     if (lstop) then
        flag_sortie = .false.
        xio=x0+l*u
        yio=y0+l*v
        zio=z0+l*w

        icell = icell0

        ! TODO : here
        if (.not.lVoronoi) then
           if (l3D) then
              if (lcylindrical) call indice_cellule(xio,yio,zio, icell)
            ! following lines are useless --> icell0 is not returned
           !else
           !   if (lcylindrical) then
           !      call verif_cell_position_cyl(icell0, xio, yio, zio)
           !   else if (lspherical) then
           !      call verif_cell_position_sph(icell0, xio, yio, zio)
           !   endif
           endif
        endif ! todo : on ne fait rien dans la cas Voronoi ???

        return
     endif ! lstop

  enddo ! boucle infinie
  write(*,*) "BUG"
  return

end subroutine physical_length

!********************************************************************

subroutine save_radiation_field(id,lambda,p_lambda,icell0, Stokes, l,  x0,y0,z0, x1,y1,z1, u,v, w, flag_star, flag_direct_star)

  integer, intent(in) :: id,lambda,p_lambda,icell0
  real(kind=db), dimension(4), intent(in) :: Stokes
  real(kind=db) :: l, x0,y0,z0, x1,y1,z1, u,v,w
  logical, intent(in) :: flag_star, flag_direct_star


  real(kind=db) :: xm,ym,zm, phi_pos, phi_vol
  integer :: psup, phi_I, theta_I, phi_k

  if (letape_th) then
     if (lRE_LTE) xKJ_abs(icell0,id) = xKJ_abs(icell0,id) + kappa_abs_LTE(icell0,lambda) * l * Stokes(1)
     if (lxJ_abs) xJ_abs(icell0,lambda,id) = xJ_abs(icell0,lambda,id) + l * Stokes(1)
  else
     if (lProDiMo) then
        xJ_abs(icell0,lambda,id) = xJ_abs(icell0,lambda,id) + l * Stokes(1)
        ! Pour statistique: nbre de paquet contribuant a intensite specifique
        xN_abs(icell0,lambda,id) = xN_abs(icell0,lambda,id) + 1.0
     endif ! lProDiMo

     if (loutput_UV_field) xJ_abs(icell0,lambda,id) = xJ_abs(icell0,lambda,id) + l * Stokes(1)

     if (lscatt_ray_tracing1) then
        xm = 0.5_db * (x0 + x1)
        ym = 0.5_db * (y0 + y1)
        zm = 0.5_db * (z0 + z1)

        if (l3D) then ! phik & psup=1 in 3D
           phi_k = 1
           psup = 1
        else
           phi_pos = atan2(ym,xm)
           phi_k = floor(  modulo(phi_pos, deux_pi) / deux_pi * n_az_rt ) + 1
           if (phi_k > n_az_rt) phi_k=n_az_rt

           if (zm > 0.0_db) then
              psup = 1
           else
              psup = 2
           endif
        endif

        if (lsepar_pola) then
           call calc_xI_scatt_pola(id,lambda,p_lambda,icell0,phi_k,psup,l,Stokes(:),flag_star)
        else
           ! ralentit d'un facteur 5 le calcul de SED
           ! facteur limitant
           call calc_xI_scatt(id,lambda,p_lambda,icell0,phi_k,psup,l,Stokes(1),flag_star)
        endif

     else if (lscatt_ray_tracing2) then ! only 2D
        if (flag_direct_star) then
           I_spec_star(icell0,id) = I_spec_star(icell0,id) + l * Stokes(1)
        else
           xm = 0.5_db * (x0 + x1)
           ym = 0.5_db * (y0 + y1)
           zm = 0.5_db * (z0 + z1)
           phi_pos = atan2(ym,xm)

           phi_vol = atan2(v,u) + deux_pi ! deux_pi pour assurer diff avec phi_pos > 0


           !  if (l_sym_ima) then
           !     delta_phi = modulo(phi_vol - phi_pos, deux_pi)
           !     if (delta_phi > pi) delta_phi = deux_pi - delta_phi
           !     phi_I =  nint( delta_phi  / pi * (n_phi_I -1) ) + 1
           !     if (phi_I > n_phi_I) phi_I = n_phi_I
           !  else
           phi_I =  floor(  modulo(phi_vol - phi_pos, deux_pi) / deux_pi * n_phi_I ) + 1
           if (phi_I > n_phi_I) phi_I = 1
           !  endif

           if (zm > 0.0_db) then
              theta_I = floor(0.5_db*( w + 1.0_db) * n_theta_I) + 1
           else
              theta_I = floor(0.5_db*(-w + 1.0_db) * n_theta_I) + 1
           endif
           if (theta_I > n_theta_I) theta_I = n_theta_I

           I_spec(1:n_Stokes,theta_I,phi_I,icell0,id) = I_spec(1:n_Stokes,theta_I,phi_I,icell0,id) + l * Stokes(1:n_Stokes)

           if (lsepar_contrib) then
              if (flag_star) then
                 I_spec(n_Stokes+2,theta_I,phi_I,icell0,id) = I_spec(n_Stokes+2,theta_I,phi_I,icell0,id) + l * Stokes(1)
              else
                 I_spec(n_Stokes+4,theta_I,phi_I,icell0,id) = I_spec(n_Stokes+4,theta_I,phi_I,icell0,id) + l * Stokes(1)
              endif
           endif ! lsepar_contrib

        endif ! flag_direct_star
     endif !lscatt_ray_tracing
  endif !letape_th

  return

end subroutine save_radiation_field

!*************************************************************************************

subroutine integ_tau(lambda)

  implicit none

  integer, intent(in) :: lambda

  integer :: icell!, i

  real(kind=db), dimension(4) :: Stokes
  ! angle de visee en deg
  real :: angle
  real(kind=db) :: x0, y0, z0, u0, v0, w0
  real :: tau
  real(kind=db) :: lmin, lmax

  angle=angle_interet

  x0=0.0 ; y0=0.0 ; z0=0.0
  Stokes = 0.0_db ; Stokes(1) = 1.0_db
  w0 = 0.0 ; u0 = 1.0 ; v0 = 0.0


  call indice_cellule(x0,y0,z0, icell)
  call optical_length_tot(1,lambda,Stokes,icell,x0,y0,y0,u0,v0,w0,tau,lmin,lmax)

  !tau = 0.0
  !do i=1, n_rad
  !   tau=tau+kappa(cell_map(i,1,1),lambda)*(r_lim(i)-r_lim(i-1))
  !enddo
  write(*,*) 'Integ tau dans plan eq. = ', tau

  if (.not.lvariable_dust) then
     icell = icell_ref
     if (kappa(icell,lambda) > tiny_real) then
        write(*,*) " Column density (g/cm�)   = ", real(tau*(masse(icell)/(volume(icell)*AU_to_cm**3))/ &
             (kappa(icell,lambda)/AU_to_cm))
     endif
  endif

  Stokes = 0.0_db ; Stokes(1) = 1.0_db
  w0 = cos((angle)*pi/180.)
  u0 = sqrt(1.0-w0*w0)
  v0 = 0.0

  call indice_cellule(x0,y0,z0, icell)
  call optical_length_tot(1,lambda,Stokes,icell,x0,y0,y0,u0,v0,w0,tau,lmin,lmax)

  write(*,fmt='(" Integ tau (i =",f4.1," deg)   = ",E12.5)') angle, tau

  if (.not.lvariable_dust) then
     icell = icell_ref
     if (kappa(icell,lambda) > tiny_real) then
        write(*,*) " Column density (g/cm�)   = ", real(tau*(masse(icell)/(volume(1)*3.347929d39))/ &
             (kappa(icell,lambda)/1.49597870691e13))
     endif
  endif

  return

end subroutine integ_tau

!***********************************************************

subroutine optical_length_tot(id,lambda,Stokes,icell,xi,yi,zi,u,v,w,tau_tot_out,lmin,lmax)
! Integration par calcul de la position de l'interface entre cellules
! de l'opacite totale dans une direction donn�e
! Grille a geometrie cylindrique
! C. Pinte
! 19/04/05

  implicit none

  integer, intent(in) :: id,lambda, icell
  real(kind=db),dimension(4), intent(in) :: Stokes
  real(kind=db), intent(in) :: u,v,w
  real(kind=db), intent(in) :: xi,yi,zi
  real, intent(out) :: tau_tot_out
  real(kind=db), intent(out) :: lmin,lmax


  real(kind=db) :: x0, y0, z0, x1, y1, z1, l, ltot, tau, opacite, tau_tot, correct_plus, correct_moins
  integer :: icell0, previous_cell, next_cell

  correct_plus = 1.0_db + prec_grille
  correct_moins = 1.0_db - prec_grille

  x1=xi;y1=yi;z1=zi

  tau_tot=0.0_db

  lmin=0.0_db
  ltot=0.0_db

  next_cell = icell
  icell0 = 0 ! for previous_cell, just for Voronoi

  ! Boucle infinie sur les cellules
  do ! Boucle infinie
     ! Indice de la cellule
     previous_cell = icell0
     icell0 = next_cell
     x0=x1;y0=y1;z0=z1

     ! Test sortie
     if (test_exit_grid(icell0, x0, y0, z0)) then
        tau_tot_out=tau_tot
        lmax=ltot
        return
     endif

     if (icell0 <= n_cells) then
        opacite=kappa(icell0,lambda)
     else
        opacite = 0.0_db
     endif

     ! Calcul longeur de vol et profondeur optique dans la cellule
     call cross_cell(x0,y0,z0, u,v,w,  icell0, previous_cell, x1,y1,z1, next_cell, l)

     tau=l*opacite ! opacite constante dans la cellule

     tau_tot = tau_tot + tau
     ltot= ltot + l

     if (tau_tot < tiny_real) lmin=ltot

  enddo ! boucle infinie

  write(*,*) "BUG"
  return

end subroutine optical_length_tot

!***********************************************************

subroutine integ_ray_mol(id,icell_in,x,y,z,u,v,w,iray,labs,ispeed,tab_speed)
  ! Generalisation de la routine physical_length
  ! pour le cas du transfert dans les raies
  ! Propage un paquet depuis un point d'origine donne
  ! et integre l'equation du transfert radiatif
  ! La propagation doit etre a l'envers pour faire du
  ! ray tracing  !!
  !
  ! C. Pinte
  ! 12/04/07

  implicit none

  integer, intent(in) :: id, icell_in, iray
  real(kind=db), intent(in) :: u,v,w
  real(kind=db), intent(in) :: x,y,z
  logical, intent(in) :: labs
  integer, dimension(2), intent(in) :: ispeed
  real(kind=db), dimension(ispeed(1):ispeed(2)), intent(in) :: tab_speed

  real(kind=db), dimension(ispeed(1):ispeed(2)) :: tspeed
  real(kind=db) :: x0, y0, z0, x1, y1, z1, xphi, yphi, zphi
  real(kind=db) :: delta_vol, l, delta_vol_phi, v0, v1, v_avg0
  real(kind=db), dimension(ispeed(1):ispeed(2)) :: P, dtau, dtau2, Snu, opacite
  real(kind=db), dimension(ispeed(1):ispeed(2),nTrans) :: tau, tau2
  real(kind=db) :: dtau_c, Snu_c
  real(kind=db), dimension(nTrans) :: tau_c
  integer :: iTrans, ivpoint, iiTrans, n_vpoints, nbr_cell, icell, next_cell, previous_cell

  real :: facteur_tau

  logical :: lcellule_non_vide

  integer, parameter :: n_vpoints_max = 200 ! pas super critique, presque OK avec 2 pour la simu Herbig de Peter (2x plus vite)
  real(kind=db), dimension(n_vpoints_max) :: vitesse


  x1=x;y1=y;z1=z
  x0=x;y0=y;z0=z
  next_cell = icell_in
  nbr_cell = 0

  tau(:,:) = 0.0_db
  I0(:,:,iray,id) = 0.0_db
  v_avg0 = 0.0_db

  tau_c(:) = 0.0_db
  I0c(:,iray,id) = 0.0_db

  !*** propagation dans la grille

  ! Boucle infinie sur les cellules
  infinie : do ! Boucle infinie
     ! Indice de la cellule
     icell = next_cell
     x0=x1 ; y0=y1 ; z0=z1

     if (icell <= n_cells) then
        lcellule_non_vide=.true.
     else
        lcellule_non_vide=.false.
     endif

     ! Test sortie
     if (test_exit_grid(icell, x0, y0, z0)) then
        return
     endif

     nbr_cell = nbr_cell + 1

     ! Calcul longeur de vol et profondeur optique dans la cellule
     previous_cell = 0 ! unused, just for Voronoi
     call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell, l)
     delta_vol = l

     if (lcellule_non_vide) then
        ! Differentiel de vitesse au travers de la cellule
        !dv = dv_proj(ri0,zj0,x0,y0,z0,x1,y1,z1,u,v,w)
        v0 = v_proj(icell,x0,y0,z0,u,v,w)
        v1 = v_proj(icell,x1,y1,z1,u,v,w)
        dv = abs(v1 - v0)

        ! Nbre de points d'integration en fct du differentiel de vitesse
        ! compare a la largeur de raie de la cellule de depart
        n_vpoints  = min(max(2,nint(dv/v_line(icell)*20.)),n_vpoints_max)

        ! Vitesse projete le long du trajet dans la cellule
        do ivpoint=2, n_vpoints-1
           delta_vol_phi = (real(ivpoint,kind=db))/(real(n_vpoints,kind=db)) * delta_vol
           xphi=x0+delta_vol_phi*u
           yphi=y0+delta_vol_phi*v
           zphi=z0+delta_vol_phi*w
           vitesse(ivpoint) = v_proj(icell,xphi,yphi,zphi,u,v,w)
        enddo
        vitesse(1) = v0
        vitesse(n_vpoints) = v1

        if ((nbr_cell == 1).and.labs) then
           v_avg0 = 0.0_db
           do ivpoint=1,n_vpoints
              v_avg0 = v_avg0 + vitesse(ivpoint)
           enddo
           v_avg0 = v_avg0 / real(n_vpoints,kind=db)
        endif

        ! Profil de raie local integre a multiplie par la frequence de la transition
        P(:) = 0.0_db
        do ivpoint=1,n_vpoints
           tspeed(:) = tab_speed(:) - (vitesse(ivpoint) - v_avg0)
           P(:) = P(:) + phiProf(icell,ispeed,tspeed)
        enddo
        P(:) = P(:)/n_vpoints

        if ((nbr_cell == 1).and.labs) then
           ds(iray,id) = delta_vol
           Doppler_P_x_freq(:,iray,id) = P(:)
        endif

        do iTrans=1,nTrans
           iiTrans = indice_Trans(iTrans)

           opacite(:) = kappa_mol_o_freq(icell,iiTrans) * P(:) + kappa(icell,iiTrans)

           ! Epaisseur optique
           dtau(:) =  l * opacite(:)
           dtau_c = l * kappa(icell,iiTrans)

           ! Fonction source
           Snu(:) = ( emissivite_mol_o_freq(icell,iiTrans) * P(:) &
                + emissivite_dust(icell,iiTrans) ) / (opacite(:) + 1.0e-300_db)
           Snu_c = emissivite_dust(icell,iiTrans) / (kappa(icell,iiTrans) + 1.0e-300_db)

           ! Ajout emission en sortie de cellule (=debut car on va a l'envers) ponderee par
           ! la profondeur optique jusqu'a la cellule
           !---write(*,*) ri0, zj0
           !---write(*,*) "kappa", kappa_mol_o_freq(ri0,zj0,iiTrans), kappa(iiTrans,ri0,zj0,1)
           !---write(*,*) "eps", emissivite_mol_o_freq(ri0,zj0,iiTrans)
           !---
           !---write(*,*) minval(tau(:,iTrans)), maxval(tau(:,iTrans))
           !---write(*,*) minval(dtau(:)), maxval(dtau(:))
           !---write(*,*) minval(Snu(:)), maxval(Snu(:))
           I0(:,iTrans,iray,id) = I0(:,iTrans,iray,id) + &
                exp(-tau(:,iTrans)) * (1.0_db - exp(-dtau(:))) * Snu(:)
           I0c(iTrans,iray,id) = I0c(iTrans,iray,id) + &
                exp(-tau_c(iTrans)) * (1.0_db - exp(-dtau_c)) * Snu_c

           if (lorigine.and.(.not.labs)) then
              origine_mol(:,iiTrans,icell,id) = origine_mol(:,iiTrans,icell,id) + &
                   exp(-tau(:,iTrans)) * (1.0_db - exp(-dtau(:))) * Snu(:)
           endif

           ! surface superieure ou inf
           facteur_tau = 1.0
           if (lonly_top    .and. z0 < 0.) facteur_tau = 0.0
           if (lonly_bottom .and. z0 > 0.) facteur_tau = 0.0

           ! Mise a jour profondeur optique pour cellule suivante
           tau(:,iTrans) = tau(:,iTrans) + dtau(:) * facteur_tau
           tau_c(iTrans) = tau_c(iTrans) + dtau_c
        enddo

        if (ldouble_RT) then
           do iTrans=1,nTrans
              iiTrans = indice_Trans(iTrans)
              opacite(:) = kappa_mol_o_freq2(icell,iiTrans) * P(:) + kappa(icell,iiTrans)
              dtau(:) =  l * opacite(:)

              ! Ajout emission en sortie de cellule (=debut car on va a l'envers) ponderee par
              ! la profondeur optique jusqu'a la cellule
              Snu(:) = ( emissivite_mol_o_freq2(icell,iiTrans) * P(:) + &
                   emissivite_dust(icell,iiTrans) ) / (opacite(:) + 1.0e-30_db)
              I02(:,iTrans,iray,id) = I02(:,iTrans,iray,id) + &
                   exp(-tau2(:,iTrans)) * (1.0_db - exp(-dtau2(:))) * Snu(:)

              ! Mise a jour profondeur optique pour cellule suivante
              tau2(:,iTrans) = tau2(:,iTrans) + dtau2(:)
           enddo
        endif

     endif  ! lcellule_non_vide

  enddo infinie

  ! Ajout cmb, pondere par la profondeur optique totale
!  tspeed(:) = tab_speed(:) + v_avg0
!  I0(:,:,iray,id) = I0(:,:,iray,id) + Cmb(ispeed,tspeed) * exp(-tau(:,:))
!  if (ldouble_RT) then
!     I02(:,:,iray,id) = I02(:,:,iray,id) + Cmb(ispeed,tspeed) * exp(-tau2(:,:))
!  endif

  do iTrans=1,nTrans
     iiTrans = indice_Trans(iTrans)
     !I0(:,iTrans,iray,id) = I0(:,iTrans,iray,id) + tab_Cmb_mol(iiTrans) * exp(-tau(:,iTrans))
  enddo

  if (ldouble_RT) then
     do iTrans=1,nTrans
        iiTrans = indice_Trans(iTrans)
        I02(:,iTrans,iray,id) = I02(:,iTrans,iray,id) + tab_Cmb_mol(iiTrans) * exp(-tau2(:,iTrans))
     enddo
  endif

  return

end subroutine integ_ray_mol

!***********************************************************

subroutine integ_tau_mol(imol)

  implicit none

  integer, intent(in) :: imol

  real ::  norme, norme1, vmax, angle
  integer :: i, j, iTrans, n_speed, icell

  integer, dimension(2) :: ispeed
  real(kind=db), dimension(:), allocatable :: tab_speed, P


  n_speed = mol(imol)%n_speed_rt
  vmax = mol(imol)%vmax_center_rt

  allocate(tab_speed(-n_speed:n_speed), P(-n_speed:n_speed))

  ispeed(1) = -n_speed ; ispeed(2) = n_speed
  tab_speed(:) = span(-vmax,vmax,2*n_speed+1)

  angle=angle_interet

  iTrans = minval(mol(imol)%indice_Trans_rayTracing(1:mol(imol)%nTrans_raytracing))

  norme=0.0
  norme1=0.0
  do i=1, n_rad
     icell = cell_map(i,1,1)
     P(:) = phiProf(icell,ispeed,tab_speed)
     norme=norme+kappa_mol_o_freq(icell,iTrans)*(r_lim(i)-r_lim(i-1))*P(0)
     norme1=norme1 + kappa(icell,1) * (r_lim(i)-r_lim(i-1))
  enddo
  write(*,*) "tau_mol = ", norme
  write(*,*) "tau_dust=", norme1

  loop_r : do i=1,n_rad
     icell = cell_map(i,1,1)
     if (r_grid(icell) > 100.0) then
        norme=0.0
        loop_z : do j=nz, 1, -1
           icell = cell_map(i,j,1)
           P(:) = phiProf(icell,ispeed,tab_speed)
           norme=norme+kappa_mol_o_freq(icell,1)*(z_lim(i,j+1)-z_lim(i,j))*p(0)
           if (norme > 1.0) then
              write(*,*) "Vertical Tau_mol=1 (for r=100AU) at z=", z_grid(icell), "AU"
              exit loop_z
           endif
        enddo loop_z
        exit loop_r
     endif
  enddo loop_r

  !read(*,*)

  return

end subroutine integ_tau_mol

!********************************************************************

function integ_ray_dust(lambda,icell_in,x,y,z,u,v,w)
  ! Generalisation de la routine physical_length
  ! Propage un paquet depuis un point d'origine donne
  ! et integre l'equation du transfert radiatif
  ! La propagation doit etre a l'envers pour faire du
  ! ray tracing  !!
  !
  ! C. Pinte
  ! 23/01/08

  ! TODO : faire peter le phi ??? Ne sert que pour les champs de vitesse

  implicit none

  integer, intent(in) :: lambda, icell_in
  real(kind=db), intent(in) :: u,v,w
  real(kind=db), intent(in) :: x,y,z

  real(kind=db), dimension(N_type_flux) :: integ_ray_dust

  real(kind=db) :: x0, y0, z0, x1, y1, z1, xm, ym, zm, l
  integer :: icell, previous_cell, next_cell

  real(kind=db) :: tau, dtau

  logical :: lcellule_non_vide

  x1=x;y1=y;z1=z
  x0=x;y0=y;z0=z
  next_cell = icell_in

  tau = 0.0_db
  integ_ray_dust(:) = 0.0_db


  !*** propagation dans la grille

  ! Boucle infinie sur les cellules
  infinie : do ! Boucle infinie
     ! Indice de la cellule
     icell=next_cell
     x0=x1 ; y0=y1 ; z0=z1

     if (icell <= n_cells) then
        lcellule_non_vide=.true.
     else
        lcellule_non_vide=.false.
     endif

     ! Test sortie
     if (test_exit_grid(icell, x0, y0, z0)) then
        return
     endif

     ! Calcul longeur de vol et profondeur optique dans la cellule
     previous_cell = 0 ! unused, just for Voronoi
     call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell, l)

     if (lcellule_non_vide) then
        ! Epaisseur optique de la cellule
        dtau =  l * kappa(icell,lambda)

        ! Fct source au milieu du parcours dans la cellule
        xm = 0.5 * (x0 + x1)
        ym = 0.5 * (y0 + y1)
        zm = 0.5 * (z0 + z1)

        ! Ajout emission en sortie de cellule (=debut car on va a l'envers) ponderee par
        ! la profondeur optique jusqu'a la cellule
        integ_ray_dust(:) = integ_ray_dust(:) + &
             exp(-tau) * (1.0_db - exp(-dtau)) * dust_source_fct(icell, xm,ym,zm)

        ! Mise a jour profondeur optique pour cellule suivante
        tau = tau + dtau

        ! Pas besoin d'integrer trop profond
        if (tau > tau_dark_zone_obs) return
     endif  ! lcellule_non_vide

  enddo infinie

  return

end function integ_ray_dust

!***********************************************************

subroutine define_dark_zone(lambda,p_lambda,tau_max,ldiff_approx)
! Definition l'etendue de la zone noire
! definie le tableau logique l_dark_zone
! et les rayons limites r_in_opacite pour le premier rayon
! C. Pinte
! 22/04/05

  implicit none

  integer, parameter :: nbre_angle = 11

  integer, intent(in) :: lambda, p_lambda
  real, intent(in) :: tau_max
  logical, intent(in) :: ldiff_approx
  integer :: i, j, pk, n, id, icell, jj
  real(kind=db) :: x0, y0, z0, u0, v0, w0
  real :: somme, angle, dvol1, phi, r0

  logical :: flag_direct_star = .false.
  logical :: flag_star = .false.
  logical :: flag_sortie

  real(kind=db), dimension(4) :: Stokes

  do pk=1, n_az
     ri_in_dark_zone(pk)=n_rad
     ri_out_dark_zone(pk)=1
     ! �tape 1 : radialement depuis le centre
     somme = 0.0
     do1 : do i=1,n_rad
        somme=somme+kappa(cell_map(i,1,pk),lambda)*(r_lim(i)-r_lim(i-1))
        if (somme > tau_max) then
           ri_in_dark_zone(pk) = i
           exit do1
        endif
     enddo do1

     ! �tape 2 : radialement depuis rout
     somme = 0.0
     do2 : do i=n_rad,1,-1
        somme=somme+kappa(cell_map(i,1,pk),lambda)*(r_lim(i)-r_lim(i-1))
        if (somme > tau_max) then
           ri_out_dark_zone(pk) = i
           exit do2
        endif
     enddo do2
     if (ri_out_dark_zone(pk)==n_rad) ri_out_dark_zone(pk)=n_rad-1

     if (lcylindrical) then
        ! �tape 3 : verticalement
        do i=ri_in_dark_zone(pk), ri_out_dark_zone(pk)
           somme = 0.0
           do3 : do j=nz, 1, -1
              somme=somme+kappa(cell_map(i,j,pk),lambda)*(z_lim(i,j+1)-z_lim(i,j))
              if (somme > tau_max) then
                 zj_sup_dark_zone(i,pk) = j
                 exit do3
              endif
           enddo do3
        enddo

        ! �tape 3.5 : verticalement dans autre sens
        if (l3D) then
           do i=ri_in_dark_zone(pk), ri_out_dark_zone(pk)
              somme = 0.0
              do3_5 : do j=-nz, -1
                 somme=somme+kappa(cell_map(i,j,pk),lambda)*(z_lim(i,abs(j)+1)-z_lim(i,abs(j)))
                 if (somme > tau_max) then
                    zj_inf_dark_zone(i,pk) = j
                    exit do3_5
                 endif
              enddo do3_5
           enddo
        endif
     else ! spherical
        zj_sup_dark_zone(:,pk) = nz
     endif

  enddo !pk


  l_is_dark_zone = .false.
  l_dark_zone(:) = .false.

  ! �tape 4 : test sur tous les angles
  if (.not.l3D) then
     cell : do i=max(ri_in_dark_zone(1),2), ri_out_dark_zone(1)
        do j=zj_sup_dark_zone(i,1),1,-1
           icell = cell_map(i,j,1)
           do n=1,nbre_angle
              id=1
              ! position et direction vol
              angle= pi * real(n)/real(nbre_angle+1)! entre 0 et pi
              x0=r_grid(icell) !x0=1.00001*r_lim(i-1) ! cellule 1 traitee a part
              y0=0.0
              z0=z_grid(icell) !z0=0.99999*z_lim(i,j+1)
              u0=cos(angle)
              v0=0.0
              w0=sin(angle)
              Stokes(:) = 0.0_db ; !Stokes(1) = 1.0_db ; ! Pourquoi c'etait a 1 ?? ca fausse les chmps de radiation !!!
              call physical_length(id,lambda,p_lambda,Stokes,icell, x0,y0,z0,u0,v0,w0, &
                   flag_star,flag_direct_star,tau_max,dvol1,flag_sortie)
              if (.not.flag_sortie) then ! le photon ne sort pas
                 ! la cellule et celles en dessous sont dans la zone noire
                 do jj=1,j
                    icell = cell_map(i,jj,1)
                    l_dark_zone(icell) = .true.
                 enddo
                 l_is_dark_zone = .true.
                 ! on passe a la cellule suivante
                 cycle cell
              endif
           enddo
        enddo
     enddo cell
  else !3D
     do pk=1, n_az
        phi = 2*pi * (real(pk)-0.5)/real(n_az)
        cell_3D : do i=max(ri_in_dark_zone(pk),2), ri_out_dark_zone(pk)
           do j=zj_sup_dark_zone(i,pk),1,-1
              icell = cell_map(i,j,pk)
              do n=1,nbre_angle
                 id=1
                 ! position et direction vol
                 angle= pi * real(n)/real(nbre_angle+1)! entre 0 et pi
                 r0=r_grid(icell)!1.00001*r_lim(i-1) ! cellule 1 traitee a part
                 x0 = r0 *cos(phi)
                 y0 = r0 * sin(phi)
                 z0=z_grid(icell)!z0.99999*z_lim(i,j+1)
                 u0=cos(angle)
                 v0=0.0
                 w0=sin(angle)
                 Stokes(:) = 0.0_db ; Stokes(1) = 1.0_db ;
                 call physical_length(id,lambda,p_lambda,Stokes,icell,x0,y0,z0,u0,v0,w0, &
                      flag_star,flag_direct_star,tau_max,dvol1,flag_sortie)
                 if (.not.flag_sortie) then ! le photon ne sort pas
                    ! la cellule et celles en dessous sont dans la zone noire
                    do jj=1,j
                       icell = cell_map(i,jj,pk)
                       l_dark_zone(icell) = .true.
                    enddo
                    ! on passe a la cellule suivante
                    cycle cell_3D
                 endif
              enddo
           enddo
        enddo cell_3D

        cell_3D_2 : do i=max(ri_in_dark_zone(pk),2), ri_out_dark_zone(pk)
           do j=zj_inf_dark_zone(i,pk),-1
              icell = cell_map(i,j,pk)
              do n=1,nbre_angle
                 id=1
                 ! position et direction vol
                 angle= pi * real(n)/real(nbre_angle+1)! entre 0 et pi
                 r0=r_grid(icell)!1.00001*r_lim(i-1) ! cellule 1 traitee a part
                 x0 = r0 *cos(phi)
                 y0 = r0 * sin(phi)
                 z0=-z_grid(icell)!-0.99999*z_lim(i,abs(j)+1)
                 u0=cos(angle)
                 v0=0.0
                 w0=sin(angle)
                 Stokes(:) = 0.0_db ; Stokes(1) = 1.0_db ;
                 call physical_length(id,lambda,p_lambda,Stokes,icell,x0,y0,z0,u0,v0,w0, &
                      flag_star,flag_direct_star,tau_max,dvol1,flag_sortie)
                 if (.not.flag_sortie) then ! le photon ne sort pas
                    ! la cellule et celles en dessous sont dans la zone noire
                    do jj=1,-1
                       icell = cell_map(i,j,pk)
                       l_dark_zone(icell) = .true.
                    enddo
                    l_is_dark_zone=.true.
                    ! on passe a la cellule suivante
                    cycle cell_3D_2
                 endif
              enddo
           enddo
        enddo cell_3D_2
     enddo !pk
  endif !l3D

  do pk=1, n_az
     zj_sup_dark_zone(1:ri_in_dark_zone(pk)-1,pk) = zj_sup_dark_zone(ri_in_dark_zone(pk),pk)
     zj_sup_dark_zone(ri_out_dark_zone(pk)+1:n_rad,pk) = zj_sup_dark_zone(ri_out_dark_zone(pk),pk)
     if (l3D) then
        zj_inf_dark_zone(1:ri_in_dark_zone(pk)-1,pk) = zj_inf_dark_zone(ri_in_dark_zone(pk),pk)
        zj_inf_dark_zone(ri_out_dark_zone(pk)+1:n_rad,pk) = zj_inf_dark_zone(ri_out_dark_zone(pk),pk)
     endif
  enddo

  if ((ldiff_approx).and.(n_rad > 1)) then
     if (minval(ri_in_dark_zone(:))==1) then
        write(*,*) "ERROR : first cell is in diffusion approximation zone"
        write(*,*) "Increase spatial grid resolution"
        stop
     endif
  endif


  if (n_zones > 1) then
     do icell=1, n_cells
        if (sum(densite_pouss(:,icell)) < tiny_real) l_dark_zone(icell) = .false.
     enddo
  endif

  do i=1, n_regions
     do j=1,nz
        l_dark_zone(cell_map(regions(i)%iRmin,j,1)) = .false.
        l_dark_zone(cell_map(regions(i)%iRmax,j,1)) = .false.
     enddo
  enddo

  return

end subroutine define_dark_zone

!***********************************************************

subroutine no_dark_zone()
! Definie les variables quand il n'y a pas de zone noire
! C . Pinte
! 22/04/05

  implicit none

  l_dark_zone(:)=.false.

  return

end subroutine no_dark_zone

!***********************************************************

subroutine define_proba_weight_emission(lambda)
  ! Augmente le poids des cellules pres de la surface
  ! par exp(-tau)
  ! Le poids est applique par weight_repartion_energie
  ! C. Pinte
  ! 19/11/08

  implicit none

  integer, intent(in) :: lambda

  real, dimension(n_cells) :: tau_min
  real(kind=db), dimension(4) :: Stokes
  real(kind=db) :: x0, y0, z0, u0, v0, w0, angle, lmin, lmax
  real :: tau
  integer :: i, j, n, id, icell
  integer, parameter :: nbre_angle = 101

  tau_min(:) = 1.e30 ;

  do icell=1,n_cells
     do n=1,nbre_angle
        id=1
        ! position et direction vol
        angle= pi * real(n)/real(nbre_angle+1)! entre 0 et pi
        i = cell_map_i(icell)
        j = cell_map_j(icell)
        x0=1.00001*r_lim(i-1) ! cellule 1 traitee a part
        y0=0.0
        z0=0.99999*z_lim(i,j+1)
        u0=cos(angle)
        v0=0.0
        w0=sin(angle)

        Stokes(:) = 0.0_db ;
        call optical_length_tot(id,lambda,Stokes,icell,x0,y0,y0,u0,v0,w0,tau,lmin,lmax)
        if (tau < tau_min(icell)) tau_min(icell) = tau

        x0 = 0.99999*r_lim(i)
        call optical_length_tot(id,lambda,Stokes,icell,x0,y0,y0,u0,v0,w0,tau,lmin,lmax)
        if (tau < tau_min(icell)) tau_min(icell) = tau

     enddo
  enddo ! icell


  weight_proba_emission(1:n_cells) =  exp(-tau_min(:))

  ! correct_E_emission sera normalise dans repartition energie
  correct_E_emission(1:n_cells) = 1.0_db / weight_proba_emission(1:n_cells)

  return

end subroutine define_proba_weight_emission

!***********************************************************

end module optical_depth
