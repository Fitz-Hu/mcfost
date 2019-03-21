MODULE Opacity

 use atmos_type, only : atmos
 use atom_type
 use spectrum_type, only : NLTEspec
 use constant
 use constantes, only				 : tiny_dp, huge_dp
 use messages
 !!use voigtfunctions, only 			 : Voigt
 use broad, only 					 : Damping
 use parametres
 use profiles, only : Profile, Profile_lambda
 !!use molecular_emission, only : v_proj


 IMPLICIT NONE

 !store the pure continuum NLTE opacities to be added to the total
 !continuum opacity after NLTEloop ends
 !double precision, dimension(:,:), allocatable :: chic_nlte, etac_nlte


 CONTAINS
 
 SUBROUTINE initCrossCoupling(id)
  integer, intent(in) :: id
  integer :: nact
  
  do nact=1,atmos%Nactiveatoms
   atmos%ActiveAtoms(nact)%ptr_atom%Uji_down(:,:,id) = 0d0!0 if j<i
   atmos%ActiveAtoms(nact)%ptr_atom%chi_up(:,:,id) = 0d0
   atmos%ActiveAtoms(nact)%ptr_atom%chi_down(:,:,id) = 0d0
   
   !init eta at the same time
   atmos%ActiveAtoms(nact)%ptr_atom%eta(:,id) = 0d0
  end do
 
 RETURN
 END SUBROUTINE initCrossCoupling

 SUBROUTINE NLTEOpacity(id, icell, x, y, z, x1, y1, z1, u, v, w, l)
  !
  !
  ! chi = Vij * (ni - gij * nj)
  ! eta = twohnu3_c2 * gij * Vij * nj
  ! Continuum:
  ! Vij = alpha
  ! gij = nstari/nstarj * exp(-hc/kT/lamba)
  ! Lines:
  ! twoHnu3/c2 = Aji/Bji
  ! gij = Bji/Bij (*rho if exists)
  ! Vij = Bij * hc/4PI * phi
  !
  !
  integer, intent(in) :: id, icell
  double precision, intent(in) :: x, y, z, x1, y1, z1, u, v, w, l
  integer :: nact, Nred, Nblue, kc, kr, i, j
  type(AtomicLine) :: line
  type(AtomicContinuum) :: cont
  type(AtomType), pointer :: aatom
  double precision, parameter :: twohc = (2. * HPLANCK * CLIGHT) / (NM_TO_M)**(3d0)
  double precision, parameter :: hc_k = (HPLANCK * CLIGHT) / (KBOLTZMANN * NM_TO_M)
  double precision, dimension(NLTEspec%Nwaves) :: Vij, exp_lambda, gij, twohnu3_c2
  double precision, allocatable :: phi(:), phiZ(:,:), psiZ(:,:)
  integer, parameter :: NvspaceMax = 100
  character(len=20) :: VoigtMethod="HUMLICEK"
  integer :: Nvspace, nv, nk
  double precision :: omegav(NvspaceMax), v0, v1, delta_vol_phi, xphi, yphi, zphi, dv, hc_4PI
  exp_lambda = dexp(-hc_k / (NLTEspec%lambda * atmos%T(icell)))
  twohnu3_c2 = twohc / NLTEspec%lambda(:)**(3d0)
  hc_4PI = HPLANCK * CLIGHT / (4d0 * PI)
  
  
  do nact = 1, atmos%Nactiveatoms
   aatom => atmos%ActiveAtoms(nact)%ptr_atom
   aatom%eta(:,id) = 0d0

   if (NLTEspec%AtomOpac%initialized(id)) then
   !Update continuum opacties only once for each angle and each thread.
   !Separated loop on b-f and b-b- transitions
   	do kc = 1, aatom%Ncont
    	cont = aatom%continua(kc)
    	Nred = cont%Nred; Nblue = cont%Nblue
    	i = cont%i; j=cont%j
        gij = 0d0
   	 	Vij = cont%alpha !Zero outside cont%Nred and cont%Nblue
    	if (aatom%n(j,icell) < tiny_dp) then
     	CALL error("too small populations")
     	CYCLE
    	end if
    	gij = aatom%nstar(i, icell)/aatom%nstar(j,icell) * exp_lambda
    	aatom%continua(kc)%gij(:,id) = gij
    	aatom%continua(kc)%Vij(:,id) = Vij

    
    !store total emissivities and opacities
    	NLTEspec%AtomOpac%chi(:,id) = NLTEspec%AtomOpac%chi(:,id) + &
    									Vij * (aatom%n(i, icell) - gij * aatom%n(j,icell))
		NLTEspec%AtomOpac%eta(:,id) = NLTEspec%AtomOpac%eta(:,id) + &
    	gij * Vij * aatom%n(j,icell) * twohnu3_c2
    	
    	aatom%eta(:,id) = aatom%eta(:,id) + gij * Vij * aatom%n(j,icell) * twohnu3_c2
        !! aatom%continua(kc)%wlam(Nblue:Nred) = hc_4PI
    !Do not forget to add continuum opacities to the all continnum opacities
    !after all populations have been converged
   	end do
   end if
    
   do kr = 1, aatom%Nline
    line = aatom%lines(kr)
    Nred = line%Nred; Nblue = line%Nblue
    i = line%i; j=line%j
    
    if ((aatom%n(j,icell) <=tiny_dp).or.(aatom%n(i,icell) <=tiny_dp)) then !no transition
     	CALL error("too small populations")
     	CYCLE
    end if 
    gij = 0d0
    Vij = 0d0

    gij = line%Bji / line%Bij
    twohnu3_c2 = line%Aji / line%Bji
    if (line%voigt)  CALL Damping(icell, aatom, kr, line%adamp)
    allocate(phi(line%Nlambda))
    if (PRT_SOLUTION=="FULL_STOKES") &
    	allocate(phiZ(3,line%Nlambda), psiZ(3,line%Nlambda))
    CALL Profile(line, icell,x,y,z,x1,y1,z1,u,v,w,l, phi, phiZ, psiZ)


     Vij(Nblue:Nred) = hc_4PI * line%Bij * phi(:) !normalized in Profile()
                                                             ! / (SQRTPI * aatom%vbroad(icell))
 
     aatom%lines(kr)%gij(:,id) = gij
     aatom%lines(kr)%Vij(:,id) = Vij     
      
     NLTEspec%AtomOpac%chi(Nblue:Nred,id) = &
     		NLTEspec%AtomOpac%chi(Nblue:Nred,id) + &
       		Vij(Nblue:Nred) * (aatom%n(i,icell)-gij(Nblue:Nred)*aatom%n(j,icell))
       		
     NLTEspec%AtomOpac%eta(Nblue:Nred,id)= &
     		NLTEspec%AtomOpac%eta(Nblue:Nred,id) + &
       		twohnu3_c2(Nblue:Nred) * gij(Nblue:Nred) * Vij(Nblue:Nred) * aatom%n(j,icell)
    aatom%eta(:,id) = aatom%eta(:,id) + &
    	twohnu3_c2(Nblue:Nred) * gij(Nblue:Nred) * Vij(Nblue:Nred) * aatom%n(j,icell)
    
     if (line%polarizable .and. PRT_SOLUTION == "FULL_STOKES") then
       do nk = 1, 3
         !magneto-optical
         NLTEspec%AtomOpac%rho_p(Nblue:Nred,nk,id) = NLTEspec%AtomOpac%rho_p(Nblue:Nred,nk,id) + &
           hc_4PI * line%Bij * (aatom%n(i,icell)-gij*aatom%n(j,icell)) * psiZ(nk,:)
         !dichroism
         NLTEspec%AtomOpac%chiQUV_p(Nblue:Nred,nk,id) = NLTEspec%AtomOpac%chiQUV_p(Nblue:Nred,nk,id) + &
           hc_4PI * line%Bij * (aatom%n(i,icell)-gij*aatom%n(j,icell)) * psiZ(nk,:)
         !emissivity
         NLTEspec%AtomOpac%etaQUV_p(Nblue:Nred,nk,id) = NLTEspec%AtomOpac%etaQUV_p(Nblue:Nred,nk,id) + &
          twohnu3_c2 * gij * hc_4PI * line%Bij * aatom%n(j,icell) * phiZ(nk,:)
       end do 
     end if
    deallocate(phi)
    if (PRT_SOLUTION=="FULL_STOKES") deallocate(phiZ, psiZ)
   end do
  
  end do !over activeatoms

 RETURN
 END SUBROUTINE NLTEOpacity


END MODULE Opacity