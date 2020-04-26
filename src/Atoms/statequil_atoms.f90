MODULE statequil_atoms

	use atmos_type, only					: ne, T, nTotal_atom, ActiveAtoms, Atoms, Natom, Nactiveatoms, nHmin, ds, elements
	use atom_type
	use spectrum_type, only					: lambda, Nlambda, Nlambda_cont, lambda_cont, Jnu_cont, Itot, dk, dk_min, dk_max, &
												eta_es, eta_c, sca_c, chi_c, chi_c_nlte, eta_c_nlte, eta0_bb, chi0_bb
	use constant
	use opacity, only 						: continuum_line
	use math, only							: locate, any_nan_infinity_matrix, any_nan_infinity_vector, is_nan_infinity, &
												linear_1D
	use parametres, only 					: ldissolve, lelectron_scattering, n_cells, lforce_lte
	use collision, only						: CollisionRate !future deprecation
	use impact, only						: Collision_Hydrogen
	use getlambda, only						: hv
	use occupation_probability, only 		: D_i, wocc_n
	use profiles, only 						: write_profile
 
	use mcfost_env, only					: dp
	use constantes, only					: tiny_dp, sigma
	use messages, only 						: error, warning
	use utils, only 						: gaussslv, interp
	use input, only 						: nb_proc

	IMPLICIT NONE

	real(kind=dp), parameter :: Tmax = 1d10
	real(kind=dp), parameter :: prec_pops = 1d-100
	character(len=50), parameter :: invpop_file = "inversion_populations.txt"
	character(len=50), parameter :: profiles_file = "line_profile.txt"
	integer, parameter :: unit_invfile = 20, unit_profiles = 25

	CONTAINS

 
	SUBROUTINE fill_collision_matrix(id, icell)
		integer, intent(in) :: icell, id
		type (AtomType), pointer :: atom
		integer :: nact
  
		do nact=1, NactiveAtoms
			atom => ActiveAtoms(nact)%ptr_atom
    
			CALL collision_matrix_atom(id, icell, atom)
  	 
			atom => NULL()
		enddo
  
	RETURN 
	END SUBROUTINE fill_collision_matrix
	


 !Occupa prob ?
	SUBROUTINE collision_matrix_atom(id, icell, atom)
		integer, intent(in) :: icell, id
		type (AtomType), intent(inout) :: atom  !, pointer

    
		atom%C(:,:,id) = 0d0
		if (atom%ID=="H") then
			atom%C(:,:,id) = Collision_Hydrogen(icell)
		else
! 			write(*,*) "Collision RH not set for large atoms"
! 			stop
! 			if (id==1) write(*,*) " Using RH routine for collision atom ", atom%ID
			write(*,*) "First test it to retrive lte results !"
			stop
			atom%C(:,:,id) = CollisionRate(icell, atom)
		end if
     
		if (any_nan_infinity_matrix(atom%C(:,:,id))>0) then
			write(*,*) atom%C(:,:,id)
			write(*,*) "Bug at compute_collision_matrix", id, icell, atom%ID, atom%n(:,icell)
			stop
		endif

  
	RETURN 
	END SUBROUTINE collision_matrix_atom

 
	SUBROUTINE initGamma_atom(id, atom)
	!see Hubeny & Mihalas 2014 eq. 14.8b

		integer, intent(in) :: id
		type (AtomType), intent(inout) :: atom!, pointer
		integer :: kc
  
  									!because atom%C(i,j) is the collision rate from state i to j
  									!but rate matrix A(i,j) = -C(j,i)
  		atom%Gamma(:,:,id) = 0.0_dp
		atom%Gamma(:,:,id) = -1.0_dp * transpose(atom%C(:,:,id))
  
	RETURN 
	END SUBROUTINE initGamma_atom
 
	SUBROUTINE initGamma(id, init_bb_only)
	! ------------------------------------------------------ !
	!for each active atom, allocate and init Gamma matrix
	!deallocated in freeAtom()
	! Collision matrix has to be allocated
	! if already allocated, simply set Gamma to its new icell
	! value.
	!
	! n(l)*Cl->lp = n(lp)*Clp->l
	! e.g.,
	! Cij = Cji * (nj/ni)^star, with Cji = C(ij) = 
	! colision rate from j to i.
	!
	! (ij = j->i = (i-1)*N + j)
	! (ji = i->j = (j-1)*N + i)
	! ------------------------------------------------------ !
		integer :: nact, Nlevel, lp, l, ij, ji, nati, natf
		integer, intent(in) :: id
		logical, intent(in), optional :: init_bb_only
		type (AtomType), pointer :: atom
		logical :: init_bb_o
		
		if (present(init_bb_only)) then
			init_bb_o = init_bb_only
		else
			init_bb_o = .false.
		endif
  
		nati = 1; natf = Nactiveatoms
		do nact = nati, natf
			atom => ActiveAtoms(nact)%ptr_atom

			call initGamma_atom(id, atom)
			if (init_bb_o) then
				call init_bb_rates_atom(id, atom)
			else
				call init_rates_atom(id,atom)
			endif

			NULLIFY(atom)
		enddo
	RETURN
	END SUBROUTINE initGamma

	
	SUBROUTINE init_rates_atom(id, atom)
		integer, intent(in) :: id
		type (AtomType), intent(inout) :: atom
		integer :: k
		
		do k=1, atom%Nline
		
			atom%lines(k)%Rij(id) = 0.0
			atom%lines(k)%Rji(id) = atom%lines(k)%Aji
					
		enddo
		
		do k=1, atom%Ncont
		
			atom%continua(k)%Rij(id) = 0.0
			atom%continua(k)%Rji(id) = 0.0
		
		enddo
		
	
	RETURN
	END SUBROUTINE init_rates_atom
	
	SUBROUTINE init_bb_rates_atom(id, atom)
		integer, intent(in) :: id
		type (AtomType), intent(inout) :: atom
		integer :: k
		
		do k=1, atom%Nline
		
			atom%lines(k)%Rij(id) = 0.0
			atom%lines(k)%Rji(id) = atom%lines(k)%Aji
		
		enddo		
	
	RETURN
	END SUBROUTINE init_bb_rates_atom
	
	subroutine calc_rates(id, icell, iray, n_rayons)
		integer, intent(in) :: id, icell, iray, n_rayons
		real(kind=dp) :: chicont, etacont
		real(kind=dp), dimension(Nlambda) :: chi_tot, eta_tot, Ieff
		integer :: nact, Nred, Nblue, kc, kr, i, j, l, a0, Nl, icell_d
		real(kind=dp) :: etau, wphi, JJ, JJb, j1, j2, I1, I2, ehnukt, twohnu3_c2
		real(kind=dp) :: wl, a1, a2
		type(AtomType), pointer :: aatom, atom

		real(kind=dp) :: wi, wj, nn, dk0

		!only with lines, continuum added during integration
		chi_tot(:) = chi0_bb(:,icell) + tiny_dp
		eta_tot(:) = eta0_bb(:,icell)
		

		if (lelectron_scattering) then
			eta_tot(:) = eta_es(:,icell)
		endif
  
		atom_loop : do nact = 1, Natom
			atom => Atoms(nact)%ptr_atom

			tr_loop : do kr = 1, atom%Ntr_line

   	
				kc = atom%at(kr)%ik !relative index of a transition among continua or lines

				Nred = atom%lines(kc)%Nred;Nblue = atom%lines(kc)%Nblue
				i = atom%lines(kc)%i;j = atom%lines(kc)%j
				
 				wj = 1.0; wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1)) !1 for H
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
					endif
				endif 
				
				if ((atom%n(i,icell)*wj/wi - atom%n(j,icell)*atom%lines(kc)%gij) > 0.0_dp) then
				
        
					chi_tot(Nblue+dk_min:Nred+dk_max) = chi_tot(Nblue+dk_min:Nred+dk_max) + &
						hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * (atom%n(i,icell)*wj/wi - atom%lines(kc)%gij*atom%n(j,icell))
       	 
					eta_tot(Nblue+dk_min:Nred+dk_max)= eta_tot(Nblue+dk_min:Nred+dk_max) + &
						atom%lines(kc)%twohnu3_c2 * atom%lines(kc)%gij * hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * atom%n(j,icell) 

				
				else !neg or null
				
! 					eta_tot(Nblue+dk_min:Nred+dk_max)= eta_tot(Nblue+dk_min:Nred+dk_max) + &
! 						atom%lines(kc)%twohnu3_c2 * atom%lines(kc)%gij * hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * atom%n(j,icell) 
					eta_tot(Nblue+dk_min:Nred+dk_max)= eta_tot(Nblue+dk_min:Nred+dk_max) + 0.0_dp
					chi_tot(Nblue+dk_min:Nred+dk_max) = chi_tot(Nblue+dk_min:Nred+dk_max) - &
						hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * (atom%n(i,icell)*wj/wi - atom%lines(kc)%gij*atom%n(j,icell))
       	 

				endif
				
			    
			end do tr_loop

			atom => NULL()

		end do atom_loop
		
		Ieff = ( Itot(:,iray,id) * exp(-ds(iray,id)*chi_tot(:)) + (eta_tot(:)/chi_tot(:)) * (1.0_dp -  exp(-ds(iray,id)*chi_tot(:))) ) / n_rayons
		if (any_nan_infinity_vector(Ieff) /= 0.0) then
			write(*,*) " Ieff", Ieff, " Ieff"
			write(*,*) " chi0_bb", chi0_bb(:,icell), 'chi0_bb'
			write(*,*) " eta0_bb", eta0_bb(:,icell), 'eta0_bb'
			stop
		endif
		!now start integrates bound rates
		aatom_loop : do nact = 1, Nactiveatoms
			aatom => ActiveAtoms(nact)%ptr_atom

			atr_loop : do kr = 1, aatom%Ntr_line

				kc = aatom%at(kr)%ik

				Nred = aatom%lines(kc)%Nred;Nblue = aatom%lines(kc)%Nblue
				i = aatom%lines(kc)%i
				j = aatom%lines(kc)%j
				
				Nl = Nred-dk_min+dk_max-Nblue+1
				a0 = Nblue+dk_min-1
				
				JJ = 0.0
				wphi = 0.0

				do l=2, Nl
 				
					wphi = wphi + 0.5 * (aatom%lines(kc)%phi_loc(l,iray,id)+aatom%lines(kc)%phi_loc(l-1,iray,id)) * 1e3*hv
					
					J1 = Ieff(a0+l) * aatom%lines(kc)%phi_loc(l,iray,id)
					J2 = Ieff(a0+l-1) * aatom%lines(kc)%phi_loc(l-1,iray,id)
 
 					JJ = JJ + 0.5 * (J1 + J2) * hv * 1d3
 					!write(*,*) iray, l, J1, J2, wphi

				enddo

				JJ = JJ / wphi

				if ((wphi < 0.7) .or. (wphi > 1.1)) then
					call write_profile(unit_profiles, icell, aatom%lines(kc), kc, wphi)
				endif
				
				!init at Aji
				aatom%lines(kc)%Rji(id) = aatom%lines(kc)%Rji(id) + JJ * aatom%lines(kc)%Bji
				aatom%lines(kc)%Rij(id) = aatom%lines(kc)%Rij(id) + JJ * aatom%lines(kc)%Bij
				
! 				if ((any_nan_infinity_vector(aatom%lines(kc)%Rji) /= 0.0)) then
! 					write(*,*) "icell=",icell," id=",id," nb_proc=", nb_proc, aatom%lines(kc)%Rji(id)
! 					write(*,*) "Rji=",aatom%lines(kc)%Rji
! 					stop
! 				endif
! 				if ((any_nan_infinity_vector(aatom%lines(kc)%Rij) /= 0.0)) then
! 					write(*,*) "icell=",icell," id=",id," nb_proc=", nb_proc, aatom%lines(kc)%Rij(id)
! 					write(*,*) " Rij=", aatom%lines(kc)%Rij
! 					stop
! 				endif

			end do atr_loop
			
			atrc_loop : do kr = aatom%Ntr_line+1, aatom%Ntr
			
	 			kc = aatom%at(kr)%ik

				i = aatom%continua(kc)%i; j = aatom%continua(kc)%j
! 				chi_ion = Elements(aatom%periodic_table)%ptr_elem%ionpot(aatom%stage(j))
! 				neff = aatom%stage(j) * sqrt(aatom%Rydberg / (aatom%E(j) - aatom%E(i)) )

				
				Nblue = aatom%continua(kc)%Nb; Nred = aatom%continua(kc)%Nr
				Nl = Nred-Nblue + 1
								
				JJ = 0.0
				JJb = 0.0
				
				icell_d = 1
				if (ldissolve) then
					if (aatom%ID=="H") icell_d = icell
				endif
				
				do l=2, Nl
					wl = ( lambda(Nblue+l-1) - lambda(Nblue+l-2) )

					a1 = aatom%continua(kc)%alpha_nu(l,icell_d)
					a2 = aatom%continua(kc)%alpha_nu(l-1,icell_d)

					J1 = Ieff(Nblue+l-1) * a1 / lambda(Nblue+l-1)
					J2 = Ieff(Nblue+l-2) * a2 / lambda(Nblue+l-2)
					
					JJ = JJ + 0.5 * (J1 + J2) * wl
										
					ehnukt = exp(-hc_k/T(icell)/lambda(Nblue+l-1))
					twohnu3_c2 = ( twohc/lambda(Nblue+l-1)**3 ) / n_rayons !because Ieff = Ieff/n_rayons
					J1 = ( Ieff(Nblue+l-1) + twohnu3_c2 ) * ehnukt * a1 / lambda(Nblue+l-1)
					
					ehnukt = exp(-hc_k/T(icell)/lambda(Nblue+l-2))
					twohnu3_c2 = ( twohc/lambda(Nblue+l-2)**3 ) / n_rayons
					J2 = ( Ieff(Nblue+l-2) + twohnu3_c2 ) * ehnukt * a2 / lambda(Nblue+l-2)
										
					JJb = JJb + 0.5 * (J1 + J2) * wl

				enddo

				aatom%continua(kc)%Rij(id) = aatom%continua(kc)%Rij(id) + fourpi_h * JJ
				aatom%continua(kc)%Rji(id) = aatom%continua(kc)%Rji(id) + fourpi_h * JJb * aatom%nstar(i,icell)/aatom%nstar(j,icell)
				

			end do atrc_loop

			aatom => NULL()

		end do aatom_loop

	return
	end subroutine calc_rates

	!occupa prob
 	!Define a negative Tex for inversion of Temperature ? because the ratio of ni/nj exists
 	!even with inversion of pops.
 	!If negative Tex, T = Tmax, just like if ni = nj*gij
 	!Opacity is then 0 and only emissivity contributes.
	SUBROUTINE calc_delta_Tex_atom(icell, atom, dT, Tex, Tion, write_neg_Tex)
		integer, intent(in) :: icell
		type(AtomType), intent(inout) :: atom
		logical, intent(in) :: write_neg_tex
		real(kind=dp), intent(out) :: dT, Tex, Tion
		integer :: nact, kr, kc, i, j
		real(kind=dp) :: deltaE_k, ratio, Tdag, gij, dT_loc, Tion_loc, Tex_loc
		real(kind=dp) :: wi, wj
		
  
		dT = 0.0_dp !for all transitions of one atom
		Tex = 0.0
		Tion = 0.0
		
		tr_loop : do kr=1, atom%Ntr
			kc = atom%at(kr)%ik
   
			SELECT CASE (atom%at(kr)%trtype)
   
			CASE ("ATOMIC_LINE")
				i = atom%lines(kc)%i; j = atom%lines(kc)%j
				wj = 1.0; wi = 1.0
! 				if (ldissolve) then
! 					if (atom%ID=="H") then
! 												!nn
! 						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
! 						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1))
! 
! 					endif
! 				endif

				if (atom%n(i,icell) <= prec_pops ) cycle tr_loop

				Tdag = atom%lines(kc)%Tex(icell)
				deltaE_k = (atom%E(j)-atom%E(i)) / KBOLTZMANN
                
				ratio = dlog(wi * atom%n(j,icell) * atom%lines(kc)%gij / (atom%n(i,icell)*wj))

				!write(*,*) "line"
				!write(*,*) "nstar:", atom%nstar(i,icell), atom%nstar(j,icell)
				!write(*,*) "n:", atom%n(i,icell), atom%n(j,icell)
				!write(*,*) "T:", T(icell), Tdag, -deltaE_k/ratio
								
				if (ratio < 0.0_dp) then
      
					atom%lines(kc)%Tex(icell) = -deltaE_k / ratio
					Tex_loc = atom%lines(kc)%Tex(icell)
       
				else		
					
! 					atom%lines(kc)%Tex(icell) = Tmax
! 					Tex_loc = atom%lines(kc)%Tex(icell)
					if (ratio == 0.0) then
						atom%lines(kc)%Tex(icell) = Tmax
						Tex_loc = atom%lines(kc)%Tex(icell)
					else !ratio > 0, T < 0
						atom%lines(kc)%Tex(icell) = -deltaE_k / ratio
						Tex_loc = atom%lines(kc)%Tex(icell)
					endif						
					
if (write_neg_tex) then
write(unit_invfile,*) "-------------------------------------------------------------------------------"				
write(unit_invfile,"('icell = '(1I9), ' atom '(1A2))") icell, atom%ID
write(unit_invfile,*) "ratio : n(j) gij / n(i))"
write(unit_invfile, '(" -> line "(1I2)"  ->  "(1I2), (3E20.7E3) )') i, j, atom%n(i,icell)*wj/wi, atom%n(j,icell) * atom%lines(kc)%gij, atom%lines(kc)%Tex(icell)
write(unit_invfile, "('log(ratio) = '(1E20.7E3), ' ratio = '(1E20.7E3) )"), ratio, exp(ratio)
write(unit_invfile,"( 'w(i)='(1E20.7E3), ' w(j)='(1E20.7E3) )") wi, wj
write(unit_invfile,"( 'n(i)='(1E20.7E3), ' n(j)='(1E20.7E3) )") atom%n(i,icell), atom%n(j,icell)
write(unit_invfile,"( 'n*(i)='(1E20.7E3), ' n*(j)='(1E20.7E3) )") atom%nstar(i,icell), atom%nstar(j,icell)
write(unit_invfile,*) "-------------------------------------------------------------------------------"				
endif
     			endif
     			!write(*,*) "loc, line:", T(icell), Tex_loc
     			
       			!dT_loc = abs(Tdag-Tex_loc)/(tiny_dp + Tex_loc)
       			 dT_loc = abs(Tdag-Tex_loc)/(tiny_dp + Tdag)
       			dT = max(dT, dT_loc)
       			Tex = max(Tex, Tex_loc)

        
    		CASE ("ATOMIC_CONTINUUM")

     			i = atom%continua(kc)%i; j = atom%continua(kc)%j
				wj = 1.0; wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(j)))

					endif
				endif
				
				if (atom%n(i,icell) <= prec_pops ) cycle tr_loop
           
      			Tdag = atom%continua(kc)%Tex(icell)

				deltaE_k = (atom%E(j)-atom%E(i)) / KBOLTZMANN
      
				!at threshold
				!i.e., deltaE is hnu0
				gij = atom%nstar(i,icell)/(atom%nstar(j,icell) ) * exp(-hc_k/atom%continua(kc)%lambda0/T(icell))
				ratio = log( wj*atom%n(i,icell)  / ( wi * atom%n(j,icell) * gij ) )

				!write(*,*) "cont"
				!write(*,*) "nstar:", atom%nstar(i,icell), atom%nstar(j,icell)
				!write(*,*) "n:", atom%n(i,icell), atom%n(j,icell)
				!write(*,*) "T:", T(icell), Tdag, deltaE_k/ratio

				if (ratio > 0.0_dp) then
				
					!ionisation temperature
					atom%continua(kc)%Tex(icell) = deltaE_k / ratio
					Tion_loc = atom%continua(kc)%Tex(icell)
					
				else
	
! 					atom%continua(kc)%Tex(icell) = Tmax
! 					Tion_loc = atom%continua(kc)%Tex(icell)
					if (ratio == 0.0) then
						atom%continua(kc)%Tex(icell) = Tmax
						Tion_loc = atom%continua(kc)%Tex(icell)
					else
						atom%continua(kc)%Tex(icell) = deltaE_k / ratio
						Tion_loc = atom%continua(kc)%Tex(icell)					
					endif

if (write_neg_tex) then				
write(unit_invfile,*) "-------------------------------------------------------------------------------"				
write(unit_invfile,"('icell = '(1I9), ' atom '(1A2))") icell, atom%ID
write(unit_invfile,*) "ratio : n(i) / (n(j) gij)"
write(unit_invfile, "(' -> cont '(1I2)' -> '(1I2), (3ES20.7E3) )") i, j, atom%n(i,icell), atom%n(j,icell) * gij, atom%lines(kc)%Tex(icell)
write(unit_invfile, "('log(ratio) = '(1ES20.7E3), ' ratio = '(1ES20.7E3) )"), ratio, exp(ratio)
write(unit_invfile,"( 'w(i)='(1ES14.7), ' w(j)='(1ES20.7E3) )") wi, wj
write(unit_invfile,"( 'n(i)='(1ES14.7), ' n(j)='(1ES20.7E3) )") atom%n(i,icell), atom%n(j,icell)
write(unit_invfile,"( 'n*(i)='(1ES20.7E3), ' n*(j)='(1ES20.7E3) )") atom%nstar(i,icell), atom%nstar(j,icell)
write(unit_invfile,*) "-------------------------------------------------------------------------------"				
endif
				endif
     			!write(*,*) "loc, cont:", T(icell), Tion_loc
					
       			!dT_loc = abs(Tdag-Tion_loc)/(Tion_loc + tiny_dp)
       			dT_loc = abs(Tdag-Tion_loc)/(Tdag + tiny_dp)
       			dT = max(dT, dT_loc)		
       			Tion = max(Tion_loc, Tion)	
    
 
    		CASE DEFAULT
    		
     			CALL Error("Unkown transition type", atom%at(kr)%trtype)
     
  			 END SELECT
  
  		end do tr_loop
 
	RETURN
	END SUBROUTINE calc_delta_Tex_atom
 
 
	SUBROUTINE calc_Tex(icell) !for all atoms
		integer, intent(in) :: icell
		type(AtomType), pointer :: atom
		integer :: nact
		real(kind=dp) :: dT, Tex, Tion
  
		do nact=1, NactiveAtoms
			atom => ActiveAtoms(nact)%ptr_atom
   
			CALL calc_delta_Tex_atom(icell, atom, dT, Tex, Tion, .false.)
  
			atom => NULL()
		enddo
 
	RETURN
	END SUBROUTINE calc_Tex
	

	
	SUBROUTINE calc_rate_matrix(id, icell, switch_lte)
		integer, intent(in) :: id, icell
		logical, intent(in) :: switch_lte
		integer :: nact
		
		do nact=1, NactiveAtoms
			call rate_matrix_atom(id, icell, ActiveAtoms(nact)%ptr_atom, switch_lte)		
		enddo
	
	RETURN
	END SUBROUTINE 
	
	
	subroutine eliminate_delta(id, atom)
	!see Hubeny & Mihalas 2014 eq. 14.8a
	!calc the term in delta(l,l') (diagonal elements of rate matrix)
	!delta(l,l') = Gamma(l,l) = sum_l' R_ll' + C_ll' = sum_l' -Gamma(l',l) 
		integer, intent(in) :: id
		type (AtomType), intent(inout) :: atom
		integer :: l
  
		do l = 1, atom%Nlevel
			atom%Gamma(l,l,id) = 0.0_dp
			!Gamma(j,i) = -(Rij + Cij); Gamma(i,j) = -(Rji + Cji)
			!Gamma(i,i) = Rij + Cij = -sum(Gamma(j,i))
			atom%Gamma(l,l,id) = sum(-atom%Gamma(:,l,id))
		end do
  
	return
	end subroutine eliminate_delta
	
	
	!occupa prob
	SUBROUTINE rate_matrix_atom(id, icell, atom, switch_to_lte)
	!see Hubeny & Mihalas 2014 eq. 14.8a to 14.8c for the rate matrix elements
	!cannot directly remove diagonal here because rate matrix is already filled with
	! collision rates. Needs to add collision rates here otherwise.
		integer, intent(in) :: icell, id
		type (AtomType), intent(inout) :: atom
		logical, optional, intent(in) :: switch_to_lte
		integer :: kr, kc, i, j, l, Nblue, Nred, Nl
		real(kind=dp) :: wj, wi, neff
		
		if (present(switch_to_lte)) then
			!because Gamma = C
			if (switch_to_lte) return
		end if 
  
		tr_loop : do kr=1, atom%Ntr
			kc = atom%at(kr)%ik
   
			SELECT CASE (atom%at(kr)%trtype)
   
			CASE ("ATOMIC_LINE")
				i = atom%lines(kc)%i; j = atom%lines(kc)%j
				wj = 1.0
				wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1))
					else 
					
						!neff = (atom%stage(i)+1) * sqrt(atom%Rydberg / (atom%E(find_continuum(atom,j)) - atom%E(i)) )

					endif
				endif

				
				atom%Gamma(j,i,id) = atom%Gamma(j,i,id) - atom%lines(kc)%Rij(id) * wj/wi
				atom%Gamma(i,j,id) = atom%Gamma(i,j,id) - atom%lines(kc)%Rji(id)
				!!write(*,*) " line ", i, j, " Rij=", atom%lines(kc)%Rij(id)," Rji=",atom%lines(kc)%Rji(id)
				!!write(*,*) "  -> col ", " Cij=",atom%C(i,j,id)," Cji=",atom%C(j,i,id)

				     
        
			CASE ("ATOMIC_CONTINUUM")
				i = atom%continua(kc)%i; j = atom%continua(kc)%j
				wj = 1.0
				wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1))
					else 
					
						!neff = (atom%stage(i)+1) * sqrt(atom%Rydberg / (atom%E(find_continuum(atom,j)) - atom%E(i)) )

					endif
				endif

				atom%Gamma(j,i,id) = atom%Gamma(j,i,id) - atom%continua(kc)%Rij(id) * wj/wi
				atom%Gamma(i,j,id) = atom%Gamma(i,j,id) - atom%continua(kc)%Rji(id)

				!!write(*,*) " cont ", i, j, " Rij=", atom%continua(kc)%Rij(id)," Rji=",atom%continua(kc)%Rji(id)
				!!write(*,*) "  -> col ", " Cij=",atom%C(i,j,id)," Cji=",atom%C(j,i,id)

       
			CASE DEFAULT
    
				CALL Error("Unkown transition type", atom%at(kr)%trtype)
     
			END SELECT
  
		end do tr_loop

 
	RETURN
	END SUBROUTINE rate_matrix_atom

	subroutine see_atom(id, icell,atom, dM)
	! --------------------------------------------------------------------!
	! For atom atom solves for the Statistical Equilibrium Equations (SEE) 
	!
	! write matrix here
	!
	! For numerical stability, the row with the largest populations is 
	! removed (i.e., it is replaced by the mass conservation law).
	!
	! see Hubeny & Mihalas Stellar atmospheres, p. 448-450
	!	eqs 14.6 to 14.8c
	!
	!
	! --------------------------------------------------------------------!
  
		integer, intent(in) :: icell, id
		type(AtomType), intent(inout) :: atom
		integer :: lp, imaxpop, l
		real(kind=dp), intent(out) :: dM
		real(kind=dp), dimension(atom%Nlevel) :: ndag
		real(kind=dp) :: n0 = 0.0_dp, ntotal
		
		if (n0 /= 0.0_dp) call error("n0 should be zero at the moment !")
		ntotal = ( ntotal_atom(icell,atom) - n0 )
		
		ndag(:) = atom%n(:,icell) / ntotal
		imaxpop = locate(atom%n(:,icell), maxval(atom%n(:,icell)))
		!imaxpop = atom%Nlevel

		call eliminate_delta(id, atom)
		
! 		if (icell==66) then
! 			write(*,*)  "T=", T(icell), " imax=",imaxpop
! 			do l=1, atom%Nlevel
! 				do lp=1, atom%Nlevel
! 					write(*,*) "G", l, lp, atom%gamma(l,lp,id)
! 				enddo
! 			enddo
! ! 			stop
! 		endif

		atom%n(:,icell) = 0d0  
		atom%n(imaxpop,icell) = 1.0_dp
		atom%Gamma(imaxpop,:,id) = 1.0_dp
				
		if ((any_nan_infinity_matrix(atom%Gamma(:,:,id))>0)) then
			write(*,*) "BUG Gamma", " id=",id, " icell=",icell
! 			write(*,'("ilevel: "<atom%Nlevel>I14)') (l, l=1, atom%Nlevel)
			write(*,'("ilevel: "*(I14))') (l, l=1, atom%Nlevel)
			write(*,'("n: "<atom%Nlevel>ES14.5E3)') (atom%n(l,icell),l=1,atom%Nlevel)
			write(*,'("ndag: "<atom%Nlevel>ES14.5E3)') (ndag(l),l=1,atom%Nlevel)
			write(*,*) "Gamma:"
			write(*,'(<atom%Nlevel>I14)') (l, l=1, atom%Nlevel)
			do l=1, atom%Nlevel
				write(*, '(1I3, <atom%Nlevel>ES14.5E3)') l, (atom%Gamma(l,lp,id), lp=1, atom%Nlevel)	
			enddo
			write(*,*) "Radiative rates"
			do l=1, atom%Nline
				write(*,*) " line ", atom%lines(l)%i, atom%lines(l)%j
				write(*,*) "-> Rij=",atom%lines(l)%Rij(id)," Rji=",atom%lines(l)%Rji(id)
			enddo
			do l=1, atom%Ncont
				write(*,*) " cont ", atom%continua(l)%i, atom%continua(l)%j
				write(*,*) "-> Rij=",atom%continua(l)%Rij(id)," Rji=",atom%continua(l)%Rji(id)
			enddo
			stop
		end if
		
		CALL GaussSlv(atom%Gamma(:,:,id), atom%n(:,icell), atom%Nlevel)
! 		if (icell==66)then
! 			write(*,*) icell, "nnew=", atom%n(:,icell) * ntotal
! 			stop
! 		endif
		
		if ((any_nan_infinity_vector(atom%n(:,icell))>0)) then
			write(*,*) "BUG pops", " id=",id, " icell=",icell
			write(*,'("ilevel: "<atom%Nlevel>I14)') (l, l=1, atom%Nlevel)
			write(*,'("n: "<atom%Nlevel>ES14.5E3)') (atom%n(l,icell),l=1,atom%Nlevel)
			write(*,'("ndag: "<atom%Nlevel>ES14.5E3)') (ndag(l),l=1,atom%Nlevel)
			write(*,*) "Gamma:"
			write(*,'(<atom%Nlevel>I14)') (l, l=1, atom%Nlevel)
			do l=1, atom%Nlevel
				write(*, '(1I3, <atom%Nlevel>ES14.5E3)') l, (atom%Gamma(l,lp,id), lp=1, atom%Nlevel)	
			enddo
			write(*,*) "Radiative rates"
			do l=1, atom%Nline
				write(*,*) " line ", atom%lines(l)%i, atom%lines(l)%j
				write(*,*) "-> Rij=",atom%lines(l)%Rij(id)," Rji=",atom%lines(l)%Rji(id)
			enddo
			do l=1, atom%Ncont
				write(*,*) " cont ", atom%continua(l)%i, atom%continua(l)%j
				write(*,*) "-> Rij=",atom%continua(l)%Rij(id)," Rji=",atom%continua(l)%Rji(id)
			enddo
			stop
		end if
  
		dM = 0.0_dp
		ndag = ndag * ntotal
		do l=1,atom%Nlevel
		atom%n(l,icell) = atom%n(l,icell) * ntotal


! 			if (atom%n(l,icell) <= prec_pops) then !relative to ntotal
! 				atom%n(l,icell) = 0.0_dp
! 			else !denormalise
				!dM = max(dM, abs(atom%n(l,icell) - ndag(l))/atom%n(l,icell))
				dM = max(dM, abs(atom%n(l,icell)-ndag(l))/ndag(l))
! 				atom%n(l,icell) = atom%n(l,icell) * ntotal
! 			endif

		enddo
	!write(*,*) "n=", atom%n(:,icell)
	!stop

	return
	end subroutine see_atom
	
	
	SUBROUTINE update_populations(id, icell, delta, verbose, nit)
	! --------------------------------------------------------------------!
	! Performs a solution of SEE for each atom.
	!
	! to do: implements Ng's acceleration iteration here 
	! --------------------------------------------------------------------!

		integer, intent(in) :: id, icell, nit
		logical, intent(in) :: verbose
		type(AtomType), pointer :: atom
		integer :: nat, nati, natf
		logical :: accelerate = .false.
		real(kind=dp) :: dM, dT, dTex, dpop, Tion, Tex
		real(kind=dp), intent(out) :: delta
  
		dpop = 0.0_dp
		dTex = 0.0_dp
		
		if (verbose) write(*,*) " --> niter = ", nit, " id = ", id, " icell = ", icell

		nati = 1; natf = Nactiveatoms
		do nat=nati,natf !loop over each active atoms
  
			atom => ActiveAtoms(nat)%ptr_atom
			CALL SEE_atom(id, icell, atom, dM)
   !compute dTex and new values of Tex
			CALL calc_delta_Tex_atom(icell, atom, dT, Tex, Tion,.true.)
   

			!For one atoms = for all transitions
			if (verbose) then
				write(*,*) atom%ID, " -> dM = ", real(dM), " -> dT = ", real(dT)
				write(*,*) "   <::> Tex (K) = ", Tex, " Tion (K) = ", Tion, ' Te (K) = ', T(icell)
			endif
   
   !max for all atoms
			dpop = max(dpop, dM)
   ! and all transitions...
			dTex = max(dTex, dT)
			   
			atom => NULL()
		enddo
  
		!flag the one with a "*"
		delta = dTex
		!delta = dM

		!Compare all atoms
		if (verbose) then
			write(*,*) icell, "    >> *max(dT) = ", real(dTex)
			write(*,*) icell, "    >> max(dpops) = ", real(dpop)
		endif
 
	RETURN
	END SUBROUTINE update_populations
	
	
	!used only to write radiative rates computed with the converged radiation field
	!not used in the iterative scheme
	subroutine store_radiative_rates(id, icell, n_rayons, Nmaxtr, Rij, Rji, Jr)
	!continua radiative rates computed also with total I
		integer, intent(in) :: icell, n_rayons, Nmaxtr, id
		real(kind=dp), dimension(NactiveAtoms, Nmaxtr), intent(inout) :: Rij, Rji
		real(kind=dp), dimension(Nlambda) :: Jr
		integer :: kc, kr, nact, l, iray
		integer :: i, j, Nl, Nblue, Nred, a0
		real(kind=dp) :: a1, JJb, a2, di1, di2, ehnukt, twohnu3_c2, wl
		real(kind=dp) :: chi_ion, neff, Ieff1, Ieff2, JJ, wphi, J1, J2
		type (AtomType), pointer :: atom
	
		Rij(:,:) = 0.0_dp
		Rji(:,:) = 0.0_dp
		
		do nact=1, NactiveAtoms
		
			atom => Activeatoms(nact)%ptr_atom
		
			do kc=1, atom%Ntr
		
				kr = atom%at(kc)%ik
			
				select case (atom%at(kc)%trtype)
			
				case ("ATOMIC_LINE")
	
					Nred = atom%lines(kr)%Nred
					Nblue = atom%lines(kr)%Nblue
					i = atom%lines(kr)%i
					j = atom%lines(kr)%j
				
					Nl = Nred-dk_min+dk_max-Nblue+1
					a0 = Nblue+dk_min-1
					
					Rji(nact,kc) = atom%lines(kr)%Aji 

					do iray=1, n_rayons
				
						JJ = 0.0
						wphi = 0.0
					
						do l=2, Nl

							wphi = wphi + 0.5 * (atom%lines(kr)%phi_loc(l,iray,id)+atom%lines(kr)%phi_loc(l-1,iray,id)) * 1e3*hv
					
							Ieff1 = Itot(a0+l,iray,id)
					
							Ieff2 = Itot(a0+l-1,iray,id)

							J1 = Ieff1 * atom%lines(kr)%phi_loc(l,iray,id)
							J2 = Ieff2 * atom%lines(kr)%phi_loc(l-1,iray,id)

 							JJ = JJ + 0.5 * (J1 + J2) * hv * 1d3
 					

						enddo
				
						!init at Aji
						Rji(nact,kc) = Rji(nact,kc) + JJ * atom%lines(kr)%Bji / n_rayons / wphi
						Rij(nact,kc) = Rij(nact,kc) + JJ * atom%lines(kr)%Bij / n_rayons / wphi
					enddo

				case ("ATOMIC_CONTINUUM")
				
				
					i = atom%continua(kr)%i; j = atom%continua(kr)%j
					chi_ion = Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))
					neff = atom%stage(j) * sqrt(atom%Rydberg / (atom%E(j) - atom%E(i)) )

				
					Nblue = atom%continua(kr)%Nb; Nred = atom%continua(kr)%Nr
					Nl = Nred-Nblue + 1

								
					JJ = 0.0
					JJb = 0.0
				
					do l=2, Nl
						wl = ( lambda(Nblue+l-1) - lambda(Nblue+l-2) )
						di1 = D_i(icell, neff, real(atom%stage(i)), 1.0, lambda(Nblue+l-1), atom%continua(kr)%lambda0, chi_ion)
						di2 = D_i(icell, neff, real(atom%stage(i)), 1.0, lambda(Nblue+l-2), atom%continua(kr)%lambda0, chi_ion)
						a1 = interp(atom%continua(kr)%alpha,lambda_cont(atom%continua(kr)%Nblue:atom%continua(kr)%Nred), lambda(Nblue+l-1))
						a2 = interp(atom%continua(kr)%alpha,lambda_cont(atom%continua(kr)%Nblue:atom%continua(kr)%Nred), lambda(Nblue+l-2))

						J1 = Jr(Nblue+l-1) * di1 * a1 / lambda(Nblue+l-1)
						J2 = Jr(Nblue+l-2) * di2 * a2 / lambda(Nblue+l-2)
					
						JJ = JJ + 0.5 * (J1 + J2) * wl
										
						ehnukt = exp(-hc_k/T(icell)/lambda(Nblue+l-1))
						twohnu3_c2 = twohc/lambda(Nblue+l-1)**3
						J1 = ( Jr(Nblue+l-1) + twohnu3_c2 ) * ehnukt * di1 * a1 / lambda(Nblue+l-1)
					
						ehnukt = exp(-hc_k/T(icell)/lambda(Nblue+l-2))
						twohnu3_c2 = twohc/lambda(Nblue+l-2)**3
						J2 = ( Jr(Nblue+l-2) + twohnu3_c2 ) * ehnukt * di2 * a2 / lambda(Nblue+l-2)
										
						JJb = JJb + 0.5 * (J1 + J2) * wl
					enddo

					Rij(nact,kc) = fourpi_h * JJ
					Rji(nact,kc) = fourpi_h * JJb * atom%nstar(i,icell)/atom%nstar(j,icell)			
			
				case default
					call error("transition type unknown", atom%at(l)%trtype)
					
				end select
				
			enddo
		
			atom => NULL()
		enddo
		
	return
	end subroutine store_radiative_rates
	
	
	subroutine store_rate_matrices(id, icell, Nmaxlevel, Aij)
	!atom%Gamma should be filled with the value before exciting subiterations
		integer, intent(in) :: icell, Nmaxlevel, id
		real(kind=dp), dimension(NactiveAtoms, Nmaxlevel, Nmaxlevel), intent(inout) :: Aij
		integer :: nact
		type (AtomType), pointer :: atom
	
		Aij(:,:,:) = 0.0_dp
		
		do nact=1, NactiveAtoms

			atom => Activeatoms(nact)%ptr_atom
			!!call collision_matrix_atom(id, icell, atom)
			call initGamma_atom(id, atom) !init with collisions
			call rate_matrix_atom(id, icell, atom, lforce_lte) !built rate matrix with allocated radiative rate
			call eliminate_delta(id, atom)
			Aij(nact,1:atom%Nlevel,1:atom%Nlevel) = atom%Gamma(:,:,id)
			atom => NULL()
			
		enddo
		
	return
	end subroutine store_rate_matrices	
	
	subroutine calc_bb_rates(id, icell, iray, n_rayons)

		integer, intent(in) :: id, icell, iray, n_rayons
		real(kind=dp) :: chicont, etacont
		real(kind=dp), dimension(Nlambda) :: chi_tot, eta_tot
		integer :: nact, Nred, Nblue, kc, kr, i, j, l, a0, Nl
		real(kind=dp) :: etau, wphi, JJ, JJb, j1, j2, Ieff1, Ieff2
		real(kind=dp) :: dissolve, chi_ion, neff, wl
		type(AtomType), pointer :: aatom, atom

		real(kind=dp) :: wi, wj, nn, dk0

		!only with lines, continuum added during integration
		chi_tot(:) = chi0_bb(:,icell)!0.0
		eta_tot(:) = eta0_bb(:,icell)!0.0
		if (lelectron_scattering) then
			eta_tot(:) = eta_es(:,icell)
		endif
  
		atom_loop : do nact = 1, Natom!Nactiveatoms
			atom => Atoms(nact)%ptr_atom!ActiveAtoms(nact)%ptr_atom

			tr_loop : do kr = 1, atom%Ntr_line

   	
				kc = atom%at(kr)%ik !relative index of a transition among continua or lines

				Nred = atom%lines(kc)%Nred;Nblue = atom%lines(kc)%Nblue
				i = atom%lines(kc)%i;j = atom%lines(kc)%j
				
 				wj = 1.0; wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1)) !1 for H
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
					endif
				endif 
				
				if ((atom%n(i,icell)*wj/wi - atom%n(j,icell)*atom%lines(kc)%gij) > 0.0_dp) then
				
        
					chi_tot(Nblue+dk_min:Nred+dk_max) = chi_tot(Nblue+dk_min:Nred+dk_max) + &
						hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * (atom%n(i,icell)*wj/wi - atom%lines(kc)%gij*atom%n(j,icell))
       	 
					eta_tot(Nblue+dk_min:Nred+dk_max)= eta_tot(Nblue+dk_min:Nred+dk_max) + &
						atom%lines(kc)%twohnu3_c2 * atom%lines(kc)%gij * hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * atom%n(j,icell) 

				
				else !neg or null
				
! 					eta_tot(Nblue+dk_min:Nred+dk_max)= eta_tot(Nblue+dk_min:Nred+dk_max) + &
! 						atom%lines(kc)%twohnu3_c2 * atom%lines(kc)%gij * hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * atom%n(j,icell) 
					eta_tot(Nblue+dk_min:Nred+dk_max)= eta_tot(Nblue+dk_min:Nred+dk_max) + 0.0_dp
					chi_tot(Nblue+dk_min:Nred+dk_max) = chi_tot(Nblue+dk_min:Nred+dk_max) - &
						hc_fourPI * atom%lines(kc)%Bij * atom%lines(kc)%phi_loc(:,iray,id) * (atom%n(i,icell)*wj/wi - atom%lines(kc)%gij*atom%n(j,icell))
       	 

				endif
				
			    
			end do tr_loop

			atom => NULL()

		end do atom_loop
		
		
		!now start integrates bound rates
		aatom_loop : do nact = 1, Nactiveatoms
			aatom => ActiveAtoms(nact)%ptr_atom

			atr_loop : do kr = 1, aatom%Ntr_line

				!relative index of a transition among continua or lines
				kc = aatom%at(kr)%ik

				Nred = aatom%lines(kc)%Nred;Nblue = aatom%lines(kc)%Nblue
				i = aatom%lines(kc)%i
				j = aatom%lines(kc)%j
				
				Nl = Nred-dk_min+dk_max-Nblue+1
				a0 = Nblue+dk_min-1
				
				JJ = 0.0
				wphi = 0.0
				
 				!!continuum around this line
 				!!suppose that in the region where the line lies (which can be far from lambda0 if large velocity)
 				!!the continuum is constant. Might not be true
! 				if (iray==1) then
! 					!which is fastest / accurate ? eta_es already added if any
! 					!call continuum_line (icell, aatom%lines(kc)%lambda0,  aatom%lines(kc)%chi0,  aatom%lines(kc)%eta0)
! 					aatom%lines(kc)%chi0 = interp(chi_c(:,icell)+chi_c_nlte(:,icell), lambda_cont, aatom%lines(kc)%lambda0)
! 					aatom%lines(kc)%eta0 = interp(eta_c(:,icell)+eta_c_nlte(:,icell), lambda_cont, aatom%lines(kc)%lambda0)
! 				endif

				do l=2, Nl
! 				
					wphi = wphi + 0.5 * (aatom%lines(kc)%phi_loc(l,iray,id)+aatom%lines(kc)%phi_loc(l-1,iray,id)) * 1e3*hv
					
! 					etau = exp(-(chi_tot(a0+l)+aatom%lines(kc)%chi0)*ds(iray,id))
! 					Ieff1 = Itot(a0+l,iray,id) * etau + ( (eta_tot(a0+l)+aatom%lines(kc)%eta0)/(chi_tot(a0+l)+aatom%lines(kc)%chi0 + tiny_dp) ) * (1.0 - etau)
! 					
! 					etau = exp(-(chi_tot(a0+l-1)+aatom%lines(kc)%chi0)*ds(iray,id))
! 					Ieff2 = Itot(a0+l-1,iray,id) * etau + ( (eta_tot(a0+l-1)+aatom%lines(kc)%eta0)/(chi_tot(a0+l-1)+aatom%lines(kc)%chi0+tiny_dp) ) * (1.0 - etau)

					etau = exp(-chi_tot(a0+l)*ds(iray,id))
					Ieff1 = Itot(a0+l,iray,id) * etau +  (eta_tot(a0+l) / (chi_tot(a0+l) + tiny_dp) ) * (1.0 - etau)
					
					etau = exp(-chi_tot(a0+l-1)*ds(iray,id))
					Ieff2 = Itot(a0+l-1,iray,id) * etau + (eta_tot(a0+l-1) /(chi_tot(a0+l-1)+tiny_dp)) * (1.0 - etau)

					J1 = Ieff1 * aatom%lines(kc)%phi_loc(l,iray,id)
					J2 = Ieff2 * aatom%lines(kc)%phi_loc(l-1,iray,id)
! 
 					JJ = JJ + 0.5 * (J1 + J2) * hv * 1d3
 					

				enddo

				JJ = JJ / n_rayons / wphi
! 
! 				Renormalise profile ?
! 				if ((wphi < 0.95) .or. (wphi > 1.05)) then
! 					write(*,*) "icell = ", icell, " id = ", id
! 					write(*,*) " --> Beware, profile not well normalized for line ", i, j, " area = ", wphi
! 				endif
				if ((wphi < 0.7) .or. (wphi > 1.1)) then
					call write_profile(unit_profiles, icell, aatom%lines(kc), kc, wphi)
				endif
				
				!init at Aji
				aatom%lines(kc)%Rji(id) = aatom%lines(kc)%Rji(id) + JJ * aatom%lines(kc)%Bji
				aatom%lines(kc)%Rij(id) = aatom%lines(kc)%Rij(id) + JJ * aatom%lines(kc)%Bij
				
				if ((any_nan_infinity_vector(aatom%lines(kc)%Rji) /= 0.0).or.(any_nan_infinity_vector(aatom%lines(kc)%Rij))) then
					write(*,*) "icell=",icell," id=",id," nb_proc=", nb_proc, aatom%lines(kc)%Rij(id)
					write(*,*) "Rji=",aatom%lines(kc)%Rji, " Rij=", aatom%lines(kc)%Rij
					write(*,*) "I=",Itot(:,iray,id)
					write(*,*) "chi0_bb=",chi0_bb(:,icell)
					write(*,*) "eta0_bb=",eta0_bb(:,icell)
					write(*,*) "phi(iray)=", aatom%lines(kc)%phi_loc(:,iray,id)
					stop
				endif

			end do atr_loop

			aatom => NULL()

		end do aatom_loop

	return
	end subroutine calc_bb_rates

	SUBROUTINE calc_bf_rates(id, icell, Jr)
		integer, intent(in) :: id, icell
		integer :: nact
		real(kind=dp), dimension(Nlambda_cont), intent(in) :: Jr
		
		do nact=1, NactiveAtoms
		
! 			call calc_bf_rates_atom(id, icell, ActiveAtoms(nact)%ptr_atom, Jr)
			call calc_bf_rates_atom_2(id, icell, ActiveAtoms(nact)%ptr_atom, Jr)
		
		enddo
	
	RETURN
	END SUBROUTINE
 
 	!only depends on Jr(size Jnu_cont), therefore no ray integ
	SUBROUTINE calc_bf_rates_atom(id, icell, atom, Jr)

		integer, intent(in) :: icell, id
		type (AtomType), intent(inout) :: atom
		real(kind=dp), dimension(Nlambda_cont), intent(in) :: Jr
		integer :: kr, kc, i, j, l, Nblue, Nred, Nl, iray
		real(kind=dp) :: Ieff1, Ieff2, wphi, JJ, JJb, j1, j2, twohnu3_c2
		real(kind=dp) :: di1, di2, chi_ion, neff, wl, ehnukt, test_integ

		tr_loop : do kr=atom%Ntr_line+1, atom%Ntr
	 		kc = atom%at(kr)%ik
   

				i = atom%continua(kc)%i; j = atom%continua(kc)%j
				chi_ion = Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))
				neff = atom%stage(j) * sqrt(atom%Rydberg / (atom%E(j) - atom%E(i)) )

				
				Nblue = atom%continua(kc)%Nblue; Nred = atom%continua(kc)%Nred
				Nl = atom%continua(kc)%Nlambda
				
				!not useful
				atom%continua(kc)%Rij(id) = 0.0
				atom%continua(kc)%Rji(id) = 0.0
								
				JJ = 0.0
				JJb = 0.0
				
!test_integ = 0
				do l=2, Nl
					wl = lambda_cont(Nblue+l-1) - lambda_cont(Nblue+l-2)
					di1 = D_i(icell, neff, real(atom%stage(i)), 1.0, lambda_cont(Nblue+l-1), atom%continua(kc)%lambda0, chi_ion)
					di2 = D_i(icell, neff, real(atom%stage(i)), 1.0, lambda_cont(Nblue+l-2), atom%continua(kc)%lambda0, chi_ion)
					
! 					J1 = Jnu_cont(Nblue+l-1,icell) * atom%continua(kc)%alpha(l)*wl/lambda_cont(Nblue+l-1)
! 					J2 = Jnu_cont(Nblue+l-2,icell) * atom%continua(kc)%alpha(l-1)*wl/lambda_cont(Nblue+l-2)
					J1 = Jr(Nblue+l-1) * di1 * atom%continua(kc)%alpha(l)/lambda_cont(Nblue+l-1)
					J2 = Jr(Nblue+l-2) * di2 * atom%continua(kc)%alpha(l-1)/lambda_cont(Nblue+l-2)
					
					JJ = JJ + 0.5 * (J1 + J2) * wl
										
					ehnukt = exp(-hc_k/T(icell)/lambda_cont(Nblue+l-1))
					twohnu3_c2 = twohc/lambda_cont(Nblue+l-1)**3
! 					J1 = ( Jnu_cont(Nblue+l-1,icell) + atom%continua(kc)%twohnu3_c2(l)) * ehnukt * atom%continua(kc)%alpha(l) * wl/lambda_cont(Nblue+l-1)
					J1 = ( Jr(Nblue+l-1) + twohnu3_c2 ) * ehnukt * di1 * atom%continua(kc)%alpha(l) / lambda_cont(Nblue+l-1)
					ehnukt = exp(-hc_k/T(icell)/lambda_cont(Nblue+l-2))
					twohnu3_c2 = twohc/lambda_cont(Nblue+l-2)**3
! 					J2 = ( Jnu_cont(Nblue+l-2,icell) + atom%continua(kc)%twohnu3_c2(l-1)) * ehnukt * atom%continua(kc)%alpha(l-1) * wl/lambda_cont(Nblue+l-2)
					J2 = ( Jr(Nblue+l-2) + twohnu3_c2 ) * ehnukt * di2 * atom%continua(kc)%alpha(l-1) / lambda_cont(Nblue+l-2)
										
					JJb = JJb + 0.5 * (J1 + J2) * wl
!test_integ = test_integ + 0.5 * (	exp(-hc_k/T(icell)/lambda_cont(Nblue+l-1)) + exp(-hc_k/T(icell)/lambda_cont(Nblue+l-2))) * clight * (1.0/lambda_cont(Nblue+l-2) - 1.0/lambda_cont(Nblue+l-1)) * 1e9				
				enddo
!write(*,*) test_integ, KBOLTZMANN*T(icell)/Hplanck * (exp(-hc_k/T(icell)/lambda_cont(Nl+Nblue-1)) - exp(-hc_k/T(icell)/lambda_cont(Nblue)))
!stop
				atom%continua(kc)%Rij(id) = fourpi_h * JJ
				atom%continua(kc)%Rji(id) = fourpi_h * JJb * atom%nstar(i,icell)/atom%nstar(j,icell)
				
		end do tr_loop

 
	RETURN
	END SUBROUTINE calc_bf_rates_atom
	
	!Jr size Itot(:,1,1)
	SUBROUTINE calc_bf_rates_atom_2(id, icell, atom, Jr)

		integer, intent(in) :: icell, id
		type (AtomType), intent(inout) :: atom
		real(kind=dp), dimension(Nlambda), intent(in) :: Jr
		integer :: kr, kc, i, j, l, Nblue, Nred, Nl, iray
		real(kind=dp) :: Ieff1, Ieff2, wphi, JJ, JJb, j1, j2, twohnu3_c2, a1, a2
		real(kind=dp) :: di1, di2, chi_ion, neff, wl, ehnukt, test_integ

		tr_loop : do kr=atom%Ntr_line+1, atom%Ntr
	 		kc = atom%at(kr)%ik
   

				i = atom%continua(kc)%i; j = atom%continua(kc)%j
				chi_ion = Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))
				neff = atom%stage(j) * sqrt(atom%Rydberg / (atom%E(j) - atom%E(i)) )

				
				Nblue = atom%continua(kc)%Nb; Nred = atom%continua(kc)%Nr
				Nl = Nred-Nblue + 1

								
				JJ = 0.0
				JJb = 0.0
				
				do l=2, Nl
					wl = lambda(Nblue+l-1) - lambda(Nblue+l-2)
					di1 = D_i(icell, neff, real(atom%stage(i)), 1.0, lambda(Nblue+l-1), atom%continua(kc)%lambda0, chi_ion)
					di2 = D_i(icell, neff, real(atom%stage(i)), 1.0, lambda(Nblue+l-2), atom%continua(kc)%lambda0, chi_ion)
					a1 = interp(atom%continua(kc)%alpha,lambda_cont(atom%continua(kc)%Nblue:atom%continua(kc)%Nred), lambda(Nblue+l-1))
					a2 = interp(atom%continua(kc)%alpha,lambda_cont(atom%continua(kc)%Nblue:atom%continua(kc)%Nred), lambda(Nblue+l-2))

					J1 = Jr(Nblue+l-1) * di1 * a1 / lambda(Nblue+l-1)
					J2 = Jr(Nblue+l-2) * di2 * a2 / lambda(Nblue+l-2)
					
					JJ = JJ + 0.5 * (J1 + J2) * wl
										
					ehnukt = exp(-hc_k/T(icell)/lambda(Nblue+l-1))
					twohnu3_c2 = twohc/lambda(Nblue+l-1)**3
					J1 = ( Jr(Nblue+l-1) + twohnu3_c2 ) * ehnukt * di1 * a1 / lambda(Nblue+l-1)
					
					ehnukt = exp(-hc_k/T(icell)/lambda(Nblue+l-2))
					twohnu3_c2 = twohc/lambda(Nblue+l-2)**3
					J2 = ( Jr(Nblue+l-2) + twohnu3_c2 ) * ehnukt * di2 * a2 / lambda(Nblue+l-2)
										
					JJb = JJb + 0.5 * (J1 + J2) * wl
! 					if (i==1 .and. j==6) then
! 						write(*,*) "lamcont1=", lambda_cont(atom%continua(kc)%Nblue), lambda_cont(atom%continua(kc)%Nred)
! 						write(*,*) atom%continua(kc)%alpha(1), atom%continua(kc)%alpha(atom%continua(kc)%Nlambda)
! 						write(*,*) l, lambda(Nblue+l-1), lambda(Nblue+l-2)
! 						write(*,*) "alpha=", a1, " alpha2=",a2, " diss1&2=",di1, di2
! 						write(*,*) "J1&2=",Jr(Nblue+l-1), Jr(Nblue+l-2)
! 					endif
				enddo

				atom%continua(kc)%Rij(id) = fourpi_h * JJ
				atom%continua(kc)%Rji(id) = fourpi_h * JJb * atom%nstar(i,icell)/atom%nstar(j,icell)
				
		end do tr_loop

 
	RETURN
	END SUBROUTINE calc_bf_rates_atom_2		
	
	!occupa prob
	SUBROUTINE rate_matrix_atom_old(id, icell, atom, switch_to_lte)
	!Gamma init to collision rates
		integer, intent(in) :: icell, id
		type (AtomType), intent(inout) :: atom
		logical, optional, intent(in) :: switch_to_lte
		integer :: kr, kc, i, j, l, Nblue, Nred, Nl
		real(kind=dp) :: wj, wi, neff
		
		if (present(switch_to_lte)) then
			if (switch_to_lte) return
		end if 
  
		tr_loop : do kr=1, atom%Ntr
			kc = atom%at(kr)%ik
   
			SELECT CASE (atom%at(kr)%trtype)
   
			CASE ("ATOMIC_LINE")
				i = atom%lines(kc)%i; j = atom%lines(kc)%j
				wj = 1.0
				wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						!neff = (atom%stage(i)+1) * sqrt(atom%Rydberg / (atom%E(find_continuum(atom,j)) - atom%E(i)) )
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1))

					endif
				endif

				atom%Gamma(j,i,id) = atom%Gamma(j,i,id) + atom%lines(kc)%Rji(id)
				atom%Gamma(i,j,id) = atom%Gamma(i,j,id) + atom%lines(kc)%Rij(id) * wj/wi
				!!write(*,*) "l", icell, id, i, j, " Rij=", atom%lines(kc)%Rij(id), " Rji=",atom%lines(kc)%Rji(id)

				     
        
			CASE ("ATOMIC_CONTINUUM")
				i = atom%continua(kc)%i; j = atom%continua(kc)%j
				wj = 1.0
				wi = 1.0
				if (ldissolve) then
					if (atom%ID=="H") then
												!nn
						!neff = (atom%stage(i)+1) * sqrt(atom%Rydberg / (atom%E(find_continuum(atom,j)) - atom%E(i)) )
						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
					endif
				endif


				atom%Gamma(i,j,id) = atom%Gamma(i,j,id) + atom%continua(kc)%Rij(id) * wj/wi
				atom%Gamma(j,i,id) = atom%Gamma(j,i,id) + atom%continua(kc)%Rji(id)
				!!write(*,*) "c", icell, id, i, j, " Rij=", atom%continua(kc)%Rij(id), " Rji=",atom%continua(kc)%Rji(id) 
       
			CASE DEFAULT
    
				CALL Error("Unkown transition type", atom%at(kr)%trtype)
     
			END SELECT
  
		end do tr_loop

 
	RETURN
	END SUBROUTINE rate_matrix_atom_old
	
	
	SUBROUTINE remove_delta_old(id, atom)
	!Remove therm in delta(l,l')
	integer, intent(in) :: id
	type (AtomType), intent(inout) :: atom
	integer :: l
  
	do l = 1, atom%Nlevel
		atom%Gamma(l,l,id) = 0.0_dp
		atom%Gamma(l,l,id) = -sum(atom%Gamma(l,:,id))
	end do
  
	RETURN
	END SUBROUTINE remove_delta_old
	
	subroutine see_atom_old(id, icell,atom, dM)
	! --------------------------------------------------------------------!
	! For atom atom solves for the Statistical Equilibrium Equations (SEE) 
	!
	! We solve for :
	!  Sum_l' Gamma_l'l n_l' = 0 (m^-3 s^-1)
	!
	! which is equivalent in matrix notation to:
	!
	! GG(l,l') dot n_l' = 0 with l' is on the columns and l on the rows
	!
	! In particular for a 2-level atom the two equations are:
	!
	! n1*G_11 + n2*G_21 = 0
	! n1*G12 + n2*G22 = 0,
	! with one of these equations has to be replaced by
	! n1 + n2 = N
	!
	! For numerical stability, the row with the largest populations is 
	! removed (i.e., it is replaced by the mass conservation law).
	! --------------------------------------------------------------------!
  
		integer, intent(in) :: icell, id
		type(AtomType), intent(inout) :: atom
		integer :: lp, imaxpop, l
		real(kind=dp), intent(out) :: dM
		real(kind=dp), dimension(atom%Nlevel) :: ndag
		real(kind=dp) :: n0
		real(kind=dp), dimension(atom%Nlevel, atom%Nlevel) :: Aij
		
		n0 = 0.0_dp
		!-> not yet
		!!if (atom%ID=="H") n0 = nHmin(icell)
		!!if (n0 >= ntotal_atom(icell,atom)) call error("Error n0")

		CALL remove_delta_old(id, atom)


		ndag(:) = atom%n(:,icell) / ( ntotal_atom(icell,atom) - n0 )
		atom%n(:,icell) = 0d0
  
		imaxpop = locate(atom%n(:,icell), maxval(atom%n(:,icell)))
		!imaxpop = atom%Nlevel
  
		atom%n(imaxpop,icell) = 1d0
  
  		!Sum_l'_imaxpop * n_l' = N
  		!(G11 G21)  (n1)  (0)
  		!(       ) .(  ) =( )
  		!(1    1 )  (n2)  (N)
  

		atom%Gamma(:,imaxpop,id) = 1d0 !all columns of the last row for instance
		Aij = transpose(atom%Gamma(:,:,id))

		if ((any_nan_infinity_matrix(atom%Gamma(:,:,id))>0)) then
			write(*,*) "BUG Gamma", id, icell 
			write(*,*) atom%Gamma(:,:,id)
			write(*,*) "n = ", atom%n(:,icell)
			write(*,*) "ndag=", ndag
			stop
		end if
		
		CALL GaussSlv(Aij, atom%n(:,icell),atom%Nlevel)
		
		if ((any_nan_infinity_vector(atom%n(:,icell))>0)) then
			write(*,*) "BUG pops", id, icell, atom%n(:,icell)
			write(*,*) "ndag", ndag
			write(*,*) atom%Gamma(:,:,id)
			stop
		end if
  
		dM = 0.0_dp
		do l=1,atom%Nlevel

			if (atom%n(l,icell) <= prec_pops) then !relative to ntotal
				atom%n(l,icell) = 0.0_dp
			else !denormalise
				dM = max(dM, abs(atom%n(l,icell) - ndag(l))/atom%n(l,icell))
				atom%n(l,icell) = atom%n(l,icell) * ( ntotal_atom(icell,atom) - n0 )
			endif


		enddo

	return
	end subroutine see_atom_old
 

END MODULE statequil_atoms

 
! 	SUBROUTINE Gamma_LTE(id,icell)
! 	! ------------------------------------------------------------------------- !
! 	! Fill the rate matrix Gamma, whose elements are Gamma(lp,l) is the rate
! 	! of transition from level lp to l.
! 	! At initialisation, Gamma(lp,l) = C(J,I), the collisional rates from upper
! 	! level j to lower level i.
! 	!
! 	! This is the LTE case where Gamma(l',l) = C(l'l)
! 	! Gamma(l',l) = Cl'l - delta(l,l')Sum_l" (Cll").
! 	!
! 	! This Gamma is frequency and angle independent. 
! 	! FOR ALL ATOMS
! 	! ------------------------------------------------------------------------- !
! 		integer, intent(in) :: id, icell
! 		integer :: nact, kr, l, lp, nati, natf
! 		type (AtomType), pointer :: atom
! 
! 	!nati = (1. * (id-1)) / NLTEspec%NPROC * atmos%Nactiveatoms + 1
! 	!natf = (1. * id) / NLTEspec%NPROC * atmos%Nactiveatoms
! 		nati = 1; natf = Nactiveatoms
! 		do nact=nati,natf !loop over each active atoms
!    			atom => ActiveAtoms(nact)%ptr_atom
! !    do l=1,atom%Nlevel
! !     do lp=1,atom%Nlevel   
! !       atom%Gamma(lp, l) = atom%Ckij(icell, (l-1)*atom%Nlevel+lp) !lp->l; C_kij = C(j->i)
! !     end do
! !   end do
! 
!    !fill the diagonal here, delta(l',l)
!    !because for each G(i,i); Cii, Rii is 0.
!    !and Gii = -Sum_j Cij + Rij = -sum_j Gamma(i,j)
!    !diagonal of Gamma, Gamma(col,col) is sum_row Gamma(col,row)
!    !G(1,1) = - (G12 + G13 + G14 ...)
!    !G(2,2) = - (G21 + G23 + G24 ..) first index is for column and second row
!    
!    !wavelength and ray indep can remove it now
! 			do l = 1, atom%Nlevel
! 				atom%Gamma(l,l,id) = 0d0
! 				atom%Gamma(l,l,id) = -sum(atom%Gamma(l,:,id)) !sum over rows for this column
! 			enddo
! 
!    
! 			NULLIFY(atom)
!   		end do !loop over atoms
! 
! 	RETURN
! 	END SUBROUTINE Gamma_LTE
	
	!In photoionisation transition only use Icont ?
	!->compute Icont only on a small grid
	!Interpol at the end ? how to handle opac ?
! 	SUBROUTINE calc_rates_atom(id, icell, atom, n_rayons)
! 
! 		integer, intent(in) :: icell, id, n_rayons
! 		type (AtomType), intent(inout) :: atom
! 		integer :: kr, kc, i, j, l, Nblue, Nred, Nl
! 		real(kind=dp) :: Ieff, Jnu_ray, aJnu_ray, etau, wphi, Ieffp
! 		real(kind=dp) :: dissolve, chi_ion, neff, Jeff
! 		integer :: dk, iray, N1, N2
! 		integer :: dl = 2 !Do continuum integral dl by dl bins 
! 								!In this case, integrate from 1, Nl+dl,dl to take the last point !
! 
! 		tr_loop : do kr=1, atom%Ntr
! 	 		kc = atom%at(kr)%ik
!    
! 			SELECT CASE (atom%at(kr)%trtype)
!    
! 			CASE ("ATOMIC_LINE") !Rji initialized to Aji !!
! 				i = atom%lines(kc)%i; j = atom%lines(kc)%j
! 				Nblue = atom%lines(kc)%Nblue; Nred = atom%lines(kc)%Nred
! 				Nl = atom%lines(kc)%Nlambda
! 				
! 				Jnu_ray = 0.0
! 				wphi = 0.0
! 				
! 				do l=2, Nl
! 				
! 					wphi = wphi + 0.5 * (atom%lines(kc)%phi(l,icell)+atom%lines(kc)%phi(l-1,icell)) * 1e3*hv
! if (is_nan_infinity(wphi)>0) then
! write(*,*) "wphi = ", wphi
! stop
! endif					
! 					aJnu_ray = 0.0
! 					do iray=1, n_rayons
! 						dk = atom%lines(kc)%dk(iray,id)
! 
! 						etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-1-dk,iray,id))
! 						Ieffp = NLTEspec%I(Nblue+l-1-1-dk,iray,id) * etau  + (1.0_dp - etau) * NLTEspec%S(Nblue+l-1-1-dk,iray,id)
! if (is_nan_infinity(etau*Ieffp)>0) then
! write(*,*) Ieffp, etau
! stop
! endif					
! 						etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-dk,iray,id))
!        		 			Ieff = NLTEspec%I(Nblue+l-1-dk,iray,id) * etau  + (1.0_dp - etau) * NLTEspec%S(Nblue+l-1-dk,iray,id)
!        		 			aJnu_ray = aJnu_ray + 0.5 * (Ieff * atom%lines(kc)%phi(l,icell) + Ieffp * atom%lines(kc)%phi(l-1,icell))
! if (is_nan_infinity(etau*Ieff)>0) then
! write(*,*) Ieff, etau
! stop
! endif	
!       		 		enddo
!       		 		
! 					Jnu_ray = Jnu_ray + aJnu_ray
! 					
! 				enddo
! 				Jnu_ray = 1e3*hv * Jnu_ray / n_rayons / wphi
! 
! 				!Renormalise profile ?
! ! 				if ((wphi < 0.95) .or. (wphi > 1.05)) then
! ! 					write(*,*) "icell = ", icell, " id = ", id
! ! 					write(*,*) " --> Beware, profile not well normalized for line ", i, j, " area = ", wphi
! ! 				endif
! 				if ((wphi < 0.7) .or. (wphi > 1.1)) then
! 					call write_profile(unit_profiles, icell, atom%lines(kc), kc, wphi)
! 				endif
! 				
! 
! 				!init at Aji
! 				atom%lines(kc)%Rji(id) = atom%lines(kc)%Rji(id) + Jnu_ray * atom%lines(kc)%Bji
! 				atom%lines(kc)%Rij(id) = Jnu_ray * atom%lines(kc)%Bij
! 
!         
! 			CASE ("ATOMIC_CONTINUUM")
! 				i = atom%continua(kc)%i; j = atom%continua(kc)%j
! 				chi_ion = atmos%Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))
! 				neff = atom%stage(j) * sqrt(atom%Rydberg / (atom%E(j) - atom%E(i)) )
! 				
! 				
! ! 				N1 = locate(NLTEspec%lambda_cont, atom%continua(kc)%lambdamin)
! ! 				N2 = locate(NLTEspec%lambda_cont, atom%continua(kc)%lamnda0) !or lambdamax
! ! 				Nl = N2 - N1 + 1
! 				
! 				Nblue = atom%continua(kc)%Nblue; Nred = atom%continua(kc)%Nred
! 				Nl = atom%continua(kc)%N0 - Nblue + 1
! 				!Nl = atom%continua(kc)%Nlambda
! 								
! 				Jnu_ray = 0.0
! 				aJnu_ray = 0.0
! 
! 				do l=1, Nl
! 
! 					Jeff = sum( NLTEspec%Ic(Nblue+l-1,1:n_rayons,id) ) /  n_rayons
! if (is_nan_infinity(Jeff)>0) then
! write(*,*) "Jeff=", Jeff
! stop
! endif						
! 					Jnu_ray = Jnu_ray + (Jeff + atom%continua(kc)%twohnu3_c2(l)) * atom%continua(kc)%gij(l,icell) * atom%continua(kc)%alpha(l)*atom%continua(kc)%w_lam(l)
! if (is_nan_infinity(Jnu_ray)>0) then
! write(*,*) Jnu_ray
! stop
! endif	
! 					aJnu_ray = aJnu_ray + Jeff * atom%continua(kc)%alpha(l)*atom%continua(kc)%w_lam(l)
! 
! 				enddo
! 
! 				Jnu_ray = Jnu_ray / n_rayons
! 				aJnu_ray = aJnu_ray / n_rayons
! 
! 
! 				atom%continua(kc)%Rij(id) = fourpi_h * aJnu_ray
! 				atom%continua(kc)%Rji(id) = fourpi_h * Jnu_ray
! 
! 
! 			CASE DEFAULT
!     
! 				CALL Error("Unkown transition type", atom%at(kr)%trtype)
!      
! 			END SELECT
!   
! 		end do tr_loop
! 
!  
! 	RETURN
! 	END SUBROUTINE calc_rates_atom
! 	SUBROUTINE rates_atom_loc(id, icell, n_rayons, atom)
! 
! 		integer, intent(in) :: icell, id, n_rayons
! 		type (AtomType), intent(inout) :: atom
! 		integer :: kr, kc, i, j, l, Nblue, Nred, Nl
! 		real(kind=dp) :: Ieff, Jnu_ray, aJnu_ray, etau, wphi, Ieffp
! 		real(kind=dp) :: dissolve, chi_ion, neff, Jeff
! 		integer :: dk, iray
! 
! 		tr_loop : do kr=1, atom%Ntr
! 	 		kc = atom%at(kr)%ik
!    
! 			SELECT CASE (atom%at(kr)%trtype)
!    
! 			CASE ("ATOMIC_LINE") !Rji initialized to Aji !!
! 				i = atom%lines(kc)%i; j = atom%lines(kc)%j
! 				Nblue = atom%lines(kc)%Nblue; Nred = atom%lines(kc)%Nred
! 				Nl = atom%lines(kc)%Nlambda
! 
! 				
! 				Jnu_ray = 0.0
! 				wphi = 0.0
! 
! 				do l=2, Nl !Fast relatively
! 				
! 					wphi = wphi + 0.5 * (atom%lines(kc)%phi(l,icell)+atom%lines(kc)%phi(l-1,icell)) * 1e3*hv
! 
! 					do iray=1, n_rayons
! 						dk = atom%lines(kc)%dk(iray,id)
! 
! 						etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-1-dk,iray,id))
! 						Ieffp = NLTEspec%I(Nblue+l-1-1-dk,iray,id) * etau  + (1.0_dp - etau) * atom%eta(Nblue+l-1-1-dk,iray,id)/(NLTEspec%chi(Nblue+l-1-1-dk,iray,id))
! 
! 						etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-dk,iray,id))
!        		 			Ieff = NLTEspec%I(Nblue+l-1-dk,iray,id) * etau  + (1.0_dp - etau) * atom%eta(Nblue+l-1-dk,iray,id)/(NLTEspec%chi(Nblue+l-1-dk,iray,id))
!       		 
! 						Jnu_ray = Jnu_ray + 0.5 * (Ieff * atom%lines(kc)%phi(l,icell) + Ieffp * atom%lines(kc)%phi(l-1,icell))
! 					enddo
! 					
! 				enddo
! 				!Renormalise profile ?
! ! 				if ((wphi < 0.95) .or. (wphi > 1.05)) then
! ! 					write(*,*) "icell = ", icell, " id = ", id
! ! 					write(*,*) " --> Beware, profile not well normalized for line ", i, j, " area = ", wphi
! ! 				endif
! 				if ((wphi < 0.7) .or. (wphi > 1.1)) then
! 					call write_profile(unit_profiles, icell, atom%lines(kc), kc)
! 				endif
! 				
!      			Jnu_ray = 1e3 * hv * Jnu_ray / n_rayons / wphi
! 
! 				!init at Aji
! 				atom%lines(kc)%Rji(id) = atom%lines(kc)%Rji(id) + Jnu_ray * atom%lines(kc)%Bji
! 				!should be init to zero
! 				atom%lines(kc)%Rij(id) = Jnu_ray * atom%lines(kc)%Bij
! 
!         
! 			CASE ("ATOMIC_CONTINUUM")
! 				i = atom%continua(kc)%i; j = atom%continua(kc)%j
! 				Nblue = atom%continua(kc)%Nblue; Nred = atom%continua(kc)%Nred
! 				Nl = atom%continua(kc)%N0 - Nblue + 1
! 				!Nl = atom%continua(kc)%Nlambda
! 				chi_ion = atmos%Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))
! 				neff = atom%stage(j) * sqrt(atom%Rydberg / (atom%E(j) - atom%E(i)) )
! 
! 				Jnu_ray = 0.0
! 				aJnu_ray = 0.0
! 				do l=1, Nl !Can takes time
! 
! 					Jeff = 0.0
! 					do iray=1, n_rayons
! 						!etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1,iray,id))
! 						Jeff = Jeff + NLTEspec%Ic(Nblue+l-1,iray,id)! * etau + (1.0_dp - etau) * atom%eta(Nblue+l-1,iray,id)/(NLTEspec%chi(Nblue+l-1,iray,id))
! 					enddo
! 					Jeff = Jeff / n_rayons
! 					aJnu_ray = aJnu_ray + Jeff * atom%continua(kc)%alpha(l)*atom%continua(kc)%w_lam(l)
! 
! 					Jnu_ray = Jnu_ray + (Jeff + &
! 					atom%continua(kc)%twohnu3_c2(l)) * atom%continua(kc)%gij(l,icell) * atom%continua(kc)%alpha(l)*atom%continua(kc)%w_lam(l)
! 
! 
! 				enddo
! 
! 				!Should be init to zero
! 				atom%continua(kc)%Rij(id) = fourpi_h * aJnu_ray
! 				atom%continua(kc)%Rji(id) = fourpi_h * Jnu_ray
! 
! 
! 			CASE DEFAULT
!     
! 				CALL Error("Unkown transition type", atom%at(kr)%trtype)
!      
! 			END SELECT
!   
! 		end do tr_loop
! 
!  
! 	RETURN
! 	END SUBROUTINE rates_atom_loc


!  	Deprecated, does the same as calc_delta_tex but does not return the dT and dTion
! 	SUBROUTINE calc_Tex_atom(icell, atom)
! 	
! 	For lines:
! 	
! 	n(j)gij / n(i) = exp(-dE / kTex)
! 	
! 	-> Tex = -dE/k * (log(nj*gij) - log(ni))**-1
! 	
! 	
! 	For continua I define %Tex = Tion = hnu/k * 1 / log(2hnu3/c2/Snu_cont + 1), 
! 	the ionisation temperature. If Tion=Tle, Snu_cont(T=Tlte) = Bnu(Tlte) (gij = f(Tlte))
! 	
! 		integer, intent(in) :: icell
! 		type(AtomType), intent(inout) :: atom
! 		integer :: nact, kr, kc, i, j
! 		real(kind=dp) :: deltaE_k, ratio, Tex, gij, wi, wj
! 		real :: sign
! 		
! 		wi = 1.0
! 		wj = 1.0
!   
! 		tr_loop : do kr=1, atom%Ntr
! 			kc = atom%at(kr)%ik
!    
! 			SELECT CASE (atom%at(kr)%trtype)
!    
! 			CASE ("ATOMIC_LINE")
! 				i = atom%lines(kc)%i; j = atom%lines(kc)%j
! 				wj = 1.0; wi = 1.0
! 				if (ldissolve) then
! 					if (atom%ID=="H") then
! 												!nn
! 						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(i)+1))
! 						wj = wocc_n(icell, real(j,kind=dp), real(atom%stage(j)), real(atom%stage(j)+1))
! 
! 					endif
! 				endif
! 				
! 				deltaE_k = (atom%E(j)-atom%E(i)) / KBOLTZMANN
! 				ratio = dlog(wi*atom%n(j,icell) * atom%lines(kc)%gij) - dlog(wj*atom%n(i,icell))
! 				if (ratio /= 0.0) then
! 					sign negative means positive Tex, not included yet
! 					sign = real(ratio/abs(ratio))
! 
! 					should be de = hnu0
! 					atom%lines(kc)%Tex(icell) = -deltaE_k / ratio
! 					if (atom%lines(kc)%Tex(icell) < 0) then
! 						write(*,*) ratio, "Tex negative (njgij > ni) ", wi * atom%n(j,icell) * atom%lines(kc)%gij, atom%n(i,icell)*wj
! 						write(*,*) "icell = ", icell, " :: Te = ", atmos%T(icell)
!        				endif
! 				endif
!         
! 			CASE ("ATOMIC_CONTINUUM")
! 				i = atom%continua(kc)%i; j = atom%continua(kc)%j
! 				wj = 1.0; wi = 1.0
! 				if (ldissolve) then
! 					if (atom%ID=="H") then
! 												!nn
! 						wi = wocc_n(icell, real(i,kind=dp), real(atom%stage(i)), real(atom%stage(j)))
! 
! 					endif
! 				endif
!      
! 				deltaE_k = (atom%E(j)-atom%E(i)) / KBOLTZMANN
! 				ratio = dlog( atom%n(j,icell)*atom%g(i) / ( atom%n(i,icell)*atom%g(j) ) )
! 				Doesn't make sens for continua Tex = -deltaE_k / ratio
!       
! 				at threshold
! 				i.e., deltaE is hnu0
! 				gij = wi * atom%nstar(i,icell)/(1d-50 + atom%nstar(j,icell) ) * exp(-hc_k/atom%continua(kc)%lambda0/atmos%T(icell))
! 				ratio = log( atom%n(i,icell)  / ( atom%n(j,icell) * gij ) )
! 					
! 				if (ratio /= 0.0) then
! 					sign = real(ratio / abs(ratio))
! 					ionisation temperature
! 					atom%continua(kc)%Tex(icell) = deltaE_k / ratio
! 					if (atom%lines(kc)%Tex(icell) < 0) then
! 						write(*,*) ratio, "Tion negative (njgij > ni) ", atom%n(j,icell) * gij, atom%n(i,icell)
! 						write(*,*) "icell = ", icell, " :: Te = ", atmos%T(icell)
!        				endif
! 				endif
!     
!  
! 			CASE DEFAULT
!     
! 				CALL Error("Unkown transition type", atom%at(kr)%trtype)
!      
! 			END SELECT
!   
! 		end do tr_loop
! 
!  
! 	RETURN
! 	END SUBROUTINE calc_Tex_atom
	!occupa prob
  
! 	SUBROUTINE calc_rates_o(id, icell, iray, n_rayons)
! 		integer, intent(in) :: id, icell, iray, n_rayons
! 		integer :: nact
! 		
! 		do nact=1, atmos%NactiveAtoms
! 		
! 			call calc_rates_atom_o(id, icell, iray, atmos%ActiveAtoms(nact)%ptr_atom, n_rayons)
! 		
! 		enddo
! 	
! 	RETURN
! 	END SUBROUTINE 
! 
! 	!angle by angle
! 	SUBROUTINE calc_rates_atom_o(id, icell, iray, atom, n_rayons)
! 
! 		integer, intent(in) :: icell, id, n_rayons, iray
! 		type (AtomType), intent(inout) :: atom
! 		integer :: kr, kc, i, j, l, Nblue, Nred, Nl
! 		real(kind=dp) :: Ieff, Jnu_ray, aJnu_ray, etau, wphi, Ieffp
! 		real(kind=dp) :: dissolve, chi_ion, neff
! 		integer :: dk
! 		integer :: dl = 5 !Do continuum integral dl by dl bins 
! 								!In this case, integrate from 1, Nl+dl,dl to take the last point !
! 
! 		tr_loop : do kr=1, atom%Ntr
! 	 		kc = atom%at(kr)%ik
!    
! 			SELECT CASE (atom%at(kr)%trtype)
!    
! 			CASE ("ATOMIC_LINE") !Rji initialized to Aji !!
! 				i = atom%lines(kc)%i; j = atom%lines(kc)%j
! 				Nblue = atom%lines(kc)%Nblue; Nred = atom%lines(kc)%Nred
! 				Nl = atom%lines(kc)%Nlambda
! 				dk = atom%lines(kc)%dk(iray,id)
! 
! 				
! 				!Integration over frequencies for this direction
! 				!Trapezoidal rule ? Here included in the weight, except if we use hv
! 				!and in this case we integrate I*phi*dv (rectangle)
! 				
! 				Jnu_ray = 0.0
! 				wphi = 0.0
! 				!Do we need line%w_lam, since the line is linearly sampled in dv ?
! ! 				do l=1, Nl !Fast relatively
! ! 				
! ! 					wphi = wphi + atom%lines(kc)%phi(l,icell)*atom%lines(kc)%w_lam(l)
! ! 
! ! 					etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-dk,iray,id))
! !        		 		Ieff = NLTEspec%I(Nblue+l-1-dk,iray,id) * etau  + (1.0_dp - etau) * NLTEspec%S(Nblue+l-1-dk,iray,id)
! !       		 
! ! 					Jnu_ray = Jnu_ray + Ieff * atom%lines(kc)%phi(l,icell)*atom%lines(kc)%w_lam(l)
! ! 					
! ! 				enddo
! ! 				write(*,*) wphi
! ! 				wphi = 0
! ! 				!Still the first value is 0 because of the profile !
! 				do l=2, Nl !Fast relatively
! 				
! 					wphi = wphi + 0.5 * (atom%lines(kc)%phi(l,icell)+atom%lines(kc)%phi(l-1,icell)) * 1e3*hv
! 					
! 					etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-1-dk,iray,id))
! 					Ieffp = NLTEspec%I(Nblue+l-1-1-dk,iray,id) * etau  + (1.0_dp - etau) * NLTEspec%S(Nblue+l-1-1-dk,iray,id)
! 
! 					etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1-dk,iray,id))
!        		 		Ieff = NLTEspec%I(Nblue+l-1-dk,iray,id) * etau  + (1.0_dp - etau) * NLTEspec%S(Nblue+l-1-dk,iray,id)
!       		 
! 					Jnu_ray = Jnu_ray + 0.5 * (Ieff * atom%lines(kc)%phi(l,icell) + Ieffp * atom%lines(kc)%phi(l-1,icell)) * 1e3*hv
! 					
! 				enddo
! 				!Renormalise profile ?
! ! 				if ((wphi < 0.95) .or. (wphi > 1.05)) then
! ! 					write(*,*) "icell = ", icell, " id = ", id
! ! 					write(*,*) " --> Beware, profile not well normalized for line ", i, j, " area = ", wphi
! ! 				endif
! 				if ((wphi < 0.7) .or. (wphi > 1.1)) then
! 					call write_profile(unit_profiles, icell, atom%lines(kc), kc, wphi)
! 				endif
! 				
!      			Jnu_ray = Jnu_ray / n_rayons / wphi
! 
! 				!Integration over directions
! 				
! 				!atom%lines(kc)%Jbar(id) = atom%lines(kc)%Jbar(id) + Jnu_ray
! 				atom%lines(kc)%Rji(id) = atom%lines(kc)%Rji(id) + Jnu_ray * atom%lines(kc)%Bji
! 				atom%lines(kc)%Rij(id) = atom%lines(kc)%Rij(id) + Jnu_ray * atom%lines(kc)%Bij
! 
!         
! 			CASE ("ATOMIC_CONTINUUM")
! 				i = atom%continua(kc)%i; j = atom%continua(kc)%j
! 				Nblue = atom%continua(kc)%Nblue; Nred = atom%continua(kc)%Nred
! 				Nl = atom%continua(kc)%N0 - Nblue + 1
! 				!Nl = atom%continua(kc)%Nlambda
! 				chi_ion = atmos%Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))
! 				neff = atom%stage(j) * sqrt(atom%Rydberg / (atom%E(j) - atom%E(i)) )
! 
! ! if (i==1 .and. j==4) &
! ! 				write(*,*) "Nlambda = ", Nl, " iray = ", iray
! 				
! 				!Integration over frequencies for this direction
! 				!Trapezoidal rule, in the weight definition.
! 				
! 				
! 				Jnu_ray = 0.0
! 				aJnu_ray = 0.0
! 				do l=1, Nl !Can takes time
! ! 					dissolve = D_i(icell, neff, real(atom%stage(i)), 1.0, NLTEspec%lambda(Nblue+l-1), atom%continua(kc)%lambda0, chi_ion)
! ! 					Ieff = NLTEspec%I(Nblue+l-1,iray,id)*NLTEspec%etau(Nblue+l-1,iray,id) + &
! !        				 NLTEspec%Psi(Nblue+l-1,iray,id) * atom%eta(Nblue+l-1,iray,id)
!        				 
! ! 					Ieff = NLTEspec%I(Nblue+l-1,iray,id) * NLTEspec%etau(Nblue+l-1,iray,id) + &
! ! 					NLTEspec%Psi(Nblue+l-1,iray,id) * NLTEspec%S(Nblue+l-1,iray,id)
! 
! 					etau = exp(-ds(iray,id) * NLTEspec%chi(Nblue+l-1,iray,id))
! 					Ieff = NLTEspec%I(Nblue+l-1,iray,id) * etau + (1.0_dp - etau) * NLTEspec%S(Nblue+l-1,iray,id)
!        		 
! 					aJnu_ray = aJnu_ray + Ieff * atom%continua(kc)%alpha(l)*atom%continua(kc)%w_lam(l)
! 
! 					Jnu_ray = Jnu_ray + (Ieff + &
! 					atom%continua(kc)%twohnu3_c2(l)) * atom%continua(kc)%gij(l,icell) * atom%continua(kc)%alpha(l)*atom%continua(kc)%w_lam(l)
! 
! 
! 				enddo
! 
! 				!Integration over directions
! 
! 				atom%continua(kc)%Rij(id) = atom%continua(kc)%Rij(id) + fourpi_h * aJnu_ray / n_rayons
! 				atom%continua(kc)%Rji(id) = atom%continua(kc)%Rji(id) + fourpi_h * Jnu_ray / n_rayons
! 
! 
! 			CASE DEFAULT
!     
! 				CALL Error("Unkown transition type", atom%at(kr)%trtype)
!      
! 			END SELECT
!   
! 		end do tr_loop
! 
!  
! 	RETURN
! 	END SUBROUTINE calc_rates_atom_o