module phantom2mcfost

  use parametres
  use constantes

  implicit none

contains


  subroutine init_mcfost_phantom(mcfost_filename, ierr)


    character(len=*), intent(in) :: mcfost_filename
    integer, intent(out) :: ierr

    ! options
    write(*,*) "INIT MCFOST"

    ! parameter file

    ! dust properties

    ierr = 0
    return

  end subroutine init_mcfost_phantom

  !*************************************************************************

  subroutine run_mcfost_phantom(np,nptmass,ntypes,ndusttypes,npoftype,xyzh, iphase, grainsize, dustfrac, massoftype,&
       xyzmh_ptmass,hfact,umass,utime,udist,graindens, Tdust, mu_gas, ierr)

    use io_phantom

    integer, intent(in) :: np, nptmass, ntypes,ndusttypes
    real(db), dimension(4,np), intent(in) :: xyzh
    integer, dimension(np), intent(in) :: iphase
    real(db), dimension(ndusttypes,np), intent(in) :: dustfrac
    real(db), dimension(ndusttypes), intent(in) :: grainsize
    real(db), dimension(ntypes), intent(in) :: massoftype
    real(db), intent(in) :: hfact, umass, utime, udist, graindens
    real(db), dimension(:,:), intent(in) :: xyzmh_ptmass
    integer, dimension(ntypes), intent(in) :: npoftype

    real(db), dimension(np), intent(out) :: Tdust
    real(db), intent(out) :: mu_gas
    integer, intent(out) :: ierr


    real(db), dimension(:), allocatable :: x,y,z,rhogas
    real(db), dimension(:,:), allocatable :: rhodust
    integer :: ncells

    mu_gas = mu
    ierr = 0

    call phantom_2_mcfost(np,nptmass,ntypes,ndusttypes,xyzh,iphase,grainsize,dustfrac,&
         massoftype(1:ntypes),xyzmh_ptmass,hfact,umass,utime,udist,graindens,x,y,z,rhogas,rhodust,ncells)

    if (ncells <= 0) then
       ierr = 1
       return
    endif

    call setup_mcfost_Voronoi_grid()

    Tdust = 2.73

    return

  end subroutine run_mcfost_phantom

!*************************************************************************

  subroutine setup_mcfost_Voronoi_grid()

    write(*,*) "MCFOST setup Voronoi"
    return

  end subroutine setup_mcfost_Voronoi_grid

end module phantom2mcfost
