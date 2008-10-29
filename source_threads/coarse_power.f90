!! calculate mass power spectrum using coarse mesh density
  subroutine coarse_power
    implicit none
  
    include 'mpif.h'
#ifdef PPINT
    include 'cubep3m.fh'
#else
    include 'cubepm.fh'
#endif

    integer(4), parameter :: hc=nc_dim/2
    integer(4) :: i,j,k,kg
    real(4) :: kz,ky,kx,kr,k1,k2,w1,w2,pow
    character(len=7) :: z_s
    integer(4) :: fstat
    character(len=max_path) :: ofile
    real(4) :: rho_c_mean,sum_od 

    rho_c_mean=(nf_physical_dim/2)**3*mass_p/nc_dim**3

    !print *,'rank',rank,'rho_c_mean',rho_c_mean

!! First we have to change cmplx_rho_c to overdensity and re-transform

    slab=cmplx_rho_c
    call cubepm_fftw(-1)
    rho_c=rho_c/rho_c_mean-1.0
    !write(*,*) 'rank',rank,'sum(overdensity)=',sum(rho_c)
    call mpi_reduce(sum(rho_c),sum_od,1,mpi_real,mpi_sum,0,mpi_comm_world,ierr) 
    if (rank==0) write(*,*) 'total(overdensity)=',sum_od
    call cubepm_fftw(1)

!! each rank (0:nodes-1) works on it's own slab
!! slabs are decomposed in z dimension

    ps_c=0.0

    do k=1,nc_slab
!! add global offset
      kg=k+nc_slab*rank
      if (kg< hc+2) then
        kz=kg-1
      else
        kz=kg-1-nc_dim
      endif
      do j=1,nc_dim
        if (j < hc+2) then
          ky=j-1
        else
          ky=j-1-nc_dim
        endif
        do i=1,nc_dim+2,2
          kx=(i-1)/2.0
          kr=sqrt(kx**2+ky**2+kz**2)
          if (kr /= 0.0) then
            k1=ceiling(kr)
            k2=k1+1
            w1=k1-kr
            w2=1-w1
            pow=(slab(i,j,k)/nc_dim**3)**2+(slab(i+1,j,k)/nc_dim**3)**2
            ps_c(1,k1)=ps_c(1,k1)+w1
            ps_c(2,k1)=ps_c(2,k1)+w1*pow
            ps_c(1,k2)=ps_c(1,k2)+w2
            ps_c(2,k2)=ps_c(2,k2)+w2*pow
          endif
        enddo
      enddo
    enddo
   
!! Reduce ps on master node

    ps_c_sum=0.0
    call mpi_reduce(ps_c,ps_c_sum,nc_dim*2,mpi_real,mpi_sum,0,mpi_comm_world,ierr)
 
!! Divide by weights / convert P(k) to \delta^2(k)

    if (rank == 0) then
      do k=1,nc_dim
        if (ps_c_sum(1,k) /= 0) then
          ps_c_sum(2,k)=4.0*pi*((k-1)**3)*ps_c_sum(2,k)/ps_c_sum(1,k)
          ps_c_sum(1,k)=2.0*pi*(k-1)/box
        endif
      enddo

!! write power spectrum to disk 

      write(z_s,'(f7.3)') 1/a_mid - 1.0
      z_s=adjustl(z_s)
      ofile=output_path//z_s(1:len_trim(z_s))//'ps.dat'
      open(50,file=ofile,status='replace',iostat=fstat,form='formatted')

      if (fstat /= 0) then
        write(*,*) 'error:',fstat,'opening power spectrum file for write'
        write(*,*) 'rank',rank,'file:',ofile
        call mpi_abort(mpi_comm_world,ierr,ierr)
      endif

      do k=1,nc_dim
        write(50,'(2f20.10)') ps_c_sum(:,k)
      enddo

      close(50)

    endif

  end subroutine coarse_power     