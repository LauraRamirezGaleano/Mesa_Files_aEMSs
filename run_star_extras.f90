! run_star_extras aEMS models
!  ***********************************************************************
!
!     Copyright (C) 2010  Bill Paxton
!
!     this file is part of mesa.
!
!     mesa is free software; you can redistribute it and/or modify
!     it under the terms of the gnu general library public license as published
!     by the free software foundation; either version 2 of the license, or
!     (at your option) any later version.
!
!     mesa is distributed in the hope that it will be useful,
!     but without any warranty; without even the implied warranty of
!     merchantability or fitness for a particular purpose.  see the
!     gnu library general public license for more details.
!
!     you should have received a copy of the gnu library general public license
!     along with this software; if not, write to the free software
!     foundation, inc., 59 temple place, suite 330, boston, ma 02111-1307 usa
!
!     ***********************************************************************
module run_star_extras

   use star_lib
   use star_def
   use const_def
   use math_lib 
   use chem_def
   use num_lib, only: find0
 
   implicit none
 
   real(dp) :: original_diffusion_dt_limit
   logical :: rot_set_check = .false.
   logical :: TP_AGB_check = .false.
   logical :: late_AGB_check = .false.
   logical :: post_AGB_check = .false.
   logical :: pre_WD_check = .false.
 
   ! addition for the check_TP subroutine
   logical :: have_done_TP = .false.
   integer :: TP_state = 0
   integer :: TP_M_H_on = 0
   integer :: TP_M_H_min = 0
   integer :: TP_count = 0
 
 contains
 
   subroutine extras_controls(id, ierr)
     integer, intent(in) :: id
     integer, intent(out) :: ierr
     type (star_info), pointer :: s
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
 
     s% other_wind => other_set_mdot
     s% extras_startup => extras_startup
     s% extras_check_model => extras_check_model
     s% extras_finish_step => extras_finish_step
     s% extras_after_evolve => extras_after_evolve
     s% how_many_extra_history_columns => how_many_extra_history_columns
     s% data_for_extra_history_columns => data_for_extra_history_columns
     s% how_many_extra_history_header_items => how_many_extra_history_header_items
     s% data_for_extra_history_header_items => data_for_extra_history_header_items
     s% job% warn_run_star_extras =.false.
 
     s% other_adjust_mdot => my_adjust_mdot 
 
     original_diffusion_dt_limit = s% diffusion_dt_limit
 
   end subroutine extras_controls
 
 
   subroutine extras_startup(id, restart, ierr)
     integer, intent(in) :: id
     logical, intent(in) :: restart
     integer, intent(out) :: ierr
     type (star_info), pointer :: s
     integer :: j, cid
     real(dp) :: frac, vct30, vct100
     character(len=256) :: photosphere_summary, tau100_summary
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
     !extras_startup = 0
     if (.not. restart) then
        call alloc_extra_info(s)
     else
        call unpack_extra_info(s)
     end if
 
     if (.not. s% job% extras_lpar(1)) rot_set_check = .true.
 
     if(s% initial_mass < 8.0d0 .and. s% initial_mass >= 0.6d0)then
        TP_AGB_check=.true.
     endif
 
 
     if (s% star_mass <= 8.0d0) s% cool_wind_RGB_scheme ='Reimers'
 
     if(s% x_logical_ctrl(1)) then
           ! For single stars we allow to go beyong Hubble time,
           ! to reach TAMS of low mass stars
           s% max_age = -1
     endif
 
   !prototype version for increasing overshoot above 4 Msun up to the Brott et
   !al. 2011 value at 8 Msun
     s% overshoot_f(:)  = f_ov_fcn_of_mass(s% initial_mass)
 
     s% overshoot_f0(:) = 8.0d-3
 
   end subroutine extras_startup
 
   function f_ov_fcn_of_mass(m) result(f_ov)
     real(dp), intent(in) :: m
     real(dp) :: f_ov, frac
     real(dp), parameter :: f1 = 1.6d-2, f2=4.15d-2
     if(m < 4.0d0) then
        frac = 0.0d0
     elseif(m > 8.0d0) then
        frac = 1.0d0
     else
        frac = 0.5d0 * (1.0d0 - cospi(0.25d0*(m-4.0d0)))
     endif
     f_ov = f1 + (f2-f1)*frac
   end function f_ov_fcn_of_mass
 
   integer function extras_check_model(id)
     integer, intent(in) :: id
     integer :: ierr
     type (star_info), pointer :: s
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
     extras_check_model = keep_going
   end function extras_check_model
 
 integer function how_many_extra_history_header_items(id)
    integer, intent(in) :: id
    integer :: ierr
    type (star_info), pointer :: s
    ierr = 0
    call star_ptr(id, s, ierr)
    if (ierr /= 0) return
    how_many_extra_history_header_items = 0
   end function how_many_extra_history_header_items
 
   subroutine data_for_extra_history_header_items(id, n, names, vals, ierr)
      integer, intent(in) :: id, n
      character (len=maxlen_history_column_name) :: names(n)
      real(dp) :: vals(n)
      type(star_info), pointer :: s
      integer, intent(out) :: ierr
      integer :: i
      real(dp) :: Initial_X, Initial_Y, Initial_Z, initial_m
      ierr = 0
      call star_ptr(id,s,ierr)
      if(ierr/=0) return
 
      initial_X = 0._dp
      initial_Y = 0._dp
      initial_Z = 0._dp
      initial_m = 0._dp
      do i=1,s% species
          !write(*,*) chem_isos% name(s% chem_id(i)), s% xa(i,1)
          if( trim(chem_isos% name(s% chem_id(i))) == 'prot' .or. trim(chem_isos% name(s% chem_id(i))) == 'neut')then
             continue ! don't count these
          else if( trim(chem_isos% name(s% chem_id(i))) == 'h1' .or. trim(chem_isos% name(s% chem_id(i))) == 'h2' ) then
             initial_X = initial_X + s% xa(i,1)
          else if( trim(chem_isos% name(s% chem_id(i))) == 'he3' .or. trim(chem_isos% name(s% chem_id(i))) == 'he4' ) then
             initial_Y = initial_Y + s% xa(i,1)
          else
             initial_Z = initial_Z + s% xa(i,1)
          endif
       enddo
       initial_m = s% initial_mass
       names(1) = 'initial_Z'
       vals(1) = initial_Z 
   end subroutine data_for_extra_history_header_items
 
   integer function how_many_extra_history_columns(id)
     integer, intent(in) :: id
     integer :: ierr
     type (star_info), pointer :: s
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
     how_many_extra_history_columns = 26
   end function how_many_extra_history_columns
 
   subroutine data_for_extra_history_columns(id, n, names, vals, ierr)
     use chem_def, only: chem_isos
     integer, intent(in) :: id, n
     character (len=maxlen_history_column_name) :: names(n)
     real(dp) :: vals(n)
     integer, intent(out) :: ierr
     type (star_info), pointer :: s
     real(dp) :: ocz_top_radius, ocz_bot_radius, &
          ocz_top_mass, ocz_bot_mass, mixing_length_at_bcz, &
          dr, ocz_turnover_time_g, ocz_turnover_time_l_b, ocz_turnover_time_l_t, &
          env_binding_E, total_env_binding_E, MoI
     integer :: i, k, n_conv_bdy, nz, k_ocz_bot, k_ocz_top
     integer :: i1, k1, k2, j
     real(dp) :: avg_c_in_c_core
     integer ::  top_bound_zone, bot_bound_zone
     real(dp) :: m_env, Dr_env, Renv_middle, tau_conv, tau_conv_new, m_conv_core, f_conv
     real(dp) :: r_top, r_bottom, m_env_new, Dr_env_new, Renv_middle_new
     real(dp) :: conv_mx_top, conv_mx_bot, conv_mx_top_r, conv_mx_bot_r, k_div_T_posydon_new, k_div_T_posydon
       integer :: n_conv_regions_posydon
       integer,  dimension (max_num_mixing_regions) :: n_zones_of_region, bot_bdy, top_bdy
       real(dp), dimension (max_num_mixing_regions) :: cz_bot_mass_posydon
       real(dp) :: cz_bot_radius_posydon(max_num_mixing_regions)
       real(dp), dimension (max_num_mixing_regions) :: cz_top_mass_posydon, cz_top_radius_posydon
     integer :: h1, he4, c12, o16
     real(dp) :: he_core_mass_1cent,  he_core_mass_10cent, he_core_mass_30cent
     real(dp) :: he_core_radius_1cent, he_core_radius_10cent, he_core_radius_30cent
     real(dp) ::  lambda_CE_1cent, lambda_CE_10cent, lambda_CE_30cent, lambda_CE_pure_He_star_10cent
     real(dp),  dimension (:), allocatable ::  adjusted_energy
     real(dp) :: rec_energy_HII_to_HI, &
                 rec_energy_HeII_to_HeI, &
                 rec_energy_HeIII_to_HeII, &
                 diss_energy_H2, &
                 frac_HI, frac_HII, &
                 frac_HeI, frac_HeII, frac_HeIII, &
                 avg_charge_He, energy_comp
     real(dp) :: co_core_mass, co_core_radius
     integer :: co_core_k
     logical :: sticking_to_energy_without_recombination_corr
     real(dp) :: XplusY_CO_core_mass_threshold
     logical :: have_30_value, have_10_value, have_1_value, have_co_value
 
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
 
     ! output info about the CONV. ENV.: the CZ location, turnover time
     nz = s% nz
     n_conv_bdy = s% num_conv_boundaries
     i = s% n_conv_regions
     k_ocz_bot = 0
     k_ocz_top = 0
     ocz_turnover_time_g = 0.0_dp
     ocz_turnover_time_l_b = 0.0_dp
     ocz_turnover_time_l_t = 0.0_dp
     ocz_top_mass = 0.0_dp
     ocz_bot_mass = 0.0_dp
     ocz_top_radius = 0.0_dp
     ocz_bot_radius = 0.0_dp
 
     !check the outermost convection zone
     !if dM_convenv/M < 1d-8, there's no conv env.
     if (s% n_conv_regions > 0) then
        if ((s% cz_top_mass(i)/s% mstar > 0.99d0) .and. &
             ((s% cz_top_mass(i)-s% cz_bot_mass(i))/s% mstar > 1.0d-11)) then
 
           ocz_bot_mass = s% cz_bot_mass(i)
           ocz_top_mass = s% cz_top_mass(i)
           !get top radius information
           !start from k=2 (second most outer zone) in order to access k-1
           do k=2,nz
              if (s% m(k) < ocz_top_mass) then
                 ocz_top_radius = s% r(k-1)
                 k_ocz_top = k-1
                 exit
              end if
           end do
           !get top radius information
           do k=2,nz
              if (s% m(k) < ocz_bot_mass) then
                 ocz_bot_radius = s% r(k-1)
                 k_ocz_bot = k-1
                 exit
              end if
           end do
 
           !if the star is fully convective, then the bottom boundary is the center
           if ((k_ocz_bot == 0) .and. (k_ocz_top > 0)) then
              k_ocz_bot = nz
           end if
 
           !compute the "global" turnover time
           do k=k_ocz_top,k_ocz_bot
              if (k==1) cycle
              dr = s%r(k-1)-s%r(k)
              ocz_turnover_time_g = ocz_turnover_time_g + (dr/s%conv_vel(k))
           end do
 
           !compute the "local" turnover time half of a scale height above the BCZ
           mixing_length_at_bcz = s% mlt_mixing_length(k_ocz_bot)
           do k=k_ocz_top,k_ocz_bot
              if (s% r(k) < (s% r(k_ocz_bot)+0.5d0*(mixing_length_at_bcz))) then
                 ocz_turnover_time_l_b = mixing_length_at_bcz/s% conv_vel(k)
                 exit
              end if
           end do
 
           !compute the "local" turnover time one scale height above the BCZ
           do k=k_ocz_top,k_ocz_bot
              if (s% r(k) <  s% r(k_ocz_bot)+mixing_length_at_bcz ) then
                 ocz_turnover_time_l_t = mixing_length_at_bcz/s% conv_vel(k)
                 exit
              end if
           end do
        end if
     endif
 
     names(1) = 'conv_env_top_mass'
     vals(1) = ocz_top_mass/msun
     names(2) = 'conv_env_bot_mass'
     vals(2) = ocz_bot_mass/msun
     names(3) = 'conv_env_top_radius'
     vals(3) = ocz_top_radius/rsun
     names(4) = 'conv_env_bot_radius'
     vals(4) = ocz_bot_radius/rsun
     names(5) = 'conv_env_turnover_time_g'
     vals(5) = ocz_turnover_time_g
     names(6) = 'conv_env_turnover_time_l_b'
     vals(6) = ocz_turnover_time_l_b
     names(7) = 'conv_env_turnover_time_l_t'
     vals(7) = ocz_turnover_time_l_t
 
     ! output info about the ENV.: binding energy
 
     total_env_binding_E = 0.0d0
     do k=1,s% nz - 1
        if (s% m(k) > (s% he_core_mass * Msun)) then !envelope is defined to be H-rich
           env_binding_E = s% dm(k) * (s% energy(k) - (s% cgrav(k) * s% m(k+1))/s% r(k+1))
           total_env_binding_E = total_env_binding_E + env_binding_E
        end if
     end do
 
     names(8) = 'envelope_binding_energy'
     vals(8) = total_env_binding_E
 
     names(9) = 'total_moment_of_inertia'
     MoI = 0.0d0
     if(.not.s% rotation_flag)then
        do i=s% nz, 2, -1
           MoI = MoI + 0.4d0*s% dm_bar(i)*(pow5(s% r(i)) - pow5(s% r(i-1)) )/(pow3(s% r(i)) - pow3(s% r(i-1)))
        enddo
     else
        MoI = dot_product(s% dm_bar(1:s% nz), s% i_rot(1:s% nz)%val)
     endif
 
     vals(9) = MoI
 
     names(10) = "spin_parameter"
     vals(10) = clight * s% total_angular_momentum/( standard_cgrav * s% m(1) * s% m(1) )
 
     if(s% co_core_k > 0 .and. s% co_core_k < s% nz) then
         !location of c core
         k1=s% co_core_k
         !location of center
         k2=s% nz
         !locate Carbon-12 in s% xa
         do i1=1,s% species
              if(chem_isos% Z(s% chem_id(i1))==6 .and. chem_isos% Z_plus_N(s% chem_id(i1))==12)then
                  j=i1
                  exit
              endif
         enddo
         avg_c_in_c_core = dot_product(s% xa(j,k1:k2),s% dq(k1:k2))/sum(s% dq(k1:k2))
      else
         avg_c_in_c_core = 0.0d0
      endif
      names(11) = "avg_c_in_c_core"
      vals(11) = avg_c_in_c_core
 
      ! more significant covective layer for tides
      m_conv_core = mass_conv_core(s)
      m_env = 0.0_dp
      Dr_env = 0.0_dp
      Renv_middle = 0.0_dp
      m_env_new = 0.0_dp
      Dr_env_new = 0.0_dp
      Renv_middle_new = 0.0_dp
      k_div_T_posydon_new = 0.0_dp
      k_div_T_posydon = 0.0_dp
      !min_zones_for_convective_tides = 10
      f_conv = 1.0_dp ! we cannot calculate explicitly eq. 32 of Hurley et al. 2002 in single stars,
         ! beuse it is based on difference of period and spin in real binaries
             n_zones_of_region=0
             bot_bdy=0
             top_bdy=0
             cz_bot_mass_posydon=0.0_dp
             cz_bot_radius_posydon=0.0_dp
             cz_top_mass_posydon=0.0_dp
             cz_top_radius_posydon=0.0_dp
             n_conv_regions_posydon = 0
 
             call loop_conv_layers(s,n_conv_regions_posydon, n_zones_of_region, bot_bdy, top_bdy, &
             cz_bot_mass_posydon, cz_bot_radius_posydon, cz_top_mass_posydon, cz_top_radius_posydon)
      if (n_conv_regions_posydon > 0) then
        do k=1, n_conv_regions_posydon ! from inside out
          if ((cz_bot_mass_posydon(k) / Msun) >=  m_conv_core) then ! if the conv. region is not inside the conv. core
               m_env_new = (cz_top_mass_posydon(k) - cz_bot_mass_posydon(k)) / Msun
               Dr_env_new = cz_top_radius_posydon(k) - cz_bot_radius_posydon(k) ! depth of the convective layer, length of the eddie
 ! Corresponding to the Renv term in eq.31 of Hurley et al. 2002
 ! and to (R-Renv) term in eq. 4 of Rasio et al. 1996  (different notation)
             Renv_middle_new = 0.5_dp * (cz_top_radius_posydon(k) + cz_bot_radius_posydon(k) ) ! middle of the convective layer
 ! Corresponding to the (R-0.5d0*Renv) in eq.31 of Hurley et al 2002
 ! and to the Renv in eq. 4 of Rasio et al. 1996
 ! where it represented the base of the convective layer (different notation)
 
             tau_conv_new = 0.431_dp * pow( m_env_new*Dr_env_new* &
               Renv_middle_new/3d0/s% L_phot, one_third) * secyer
 
              !P_tid = 1d0/abs(1d0/porb-s% omega(top_bound_zone)/(2d0*pi))
              !f_conv = min(1.0d0, (P_tid/(2d0*tau_conv))**b% tidal_reduction)
 
              ! eq 30 of Hurley et al. 2002, assuming f_conv = 1
              k_div_T_posydon_new = (2.0_dp/21.0_dp) * (f_conv/tau_conv_new) * (m_env_new/(s% mstar/Msun))
              if (k_div_T_posydon_new >= k_div_T_posydon) then
                 m_env = m_env_new
                 Dr_env = Dr_env_new
                 Renv_middle = Renv_middle_new
                 k_div_T_posydon = k_div_T_posydon_new
                !conv_mx_top = s% cz_top_mass(k)/s% mstar !  mass coordinate of top layer
                !conv_mx_bot = s% cz_bot_mass(k)/s% mstar
                !conv_mx_top_r = r_top ! in Rsun
                !conv_mx_bot_r = r_bottom
                !write(*,'(g0)') 'Single conv_mx_top, conv_mx_bot, conv_mx_top_r, conv_mx_bot_r' , &
                !conv_mx_top, conv_mx_bot, conv_mx_top_r, conv_mx_bot_r
                !write(*,'(g0)') 'Single m_env, DR_env, Renv_middle, k/T in conv region ', k ,' is ', &
                !   m_env, Dr_env, Renv_middle, k_div_T_posydon
               end if
           end if
         end do
     end if
     names(12) = "mass_conv_reg_fortides"
     vals(12) = m_env !in solar units
     names(13) = "thickness_conv_reg_fortides"
     vals(13) = Dr_env  !in solar units
     names(14) = "radius_conv_reg_fortides"
     vals(14) = Renv_middle !in solar units
 
 
    ! lambda_CE calculation for different core definitions.
    sticking_to_energy_without_recombination_corr = .true. ! MANOS changed to no calculate recombination energy
    ! get energy from the EOS and adjust the different contributions from recombination/dissociation to internal energy
    allocate(adjusted_energy(s% nz))
    adjusted_energy=0.0d0
 
    if (sticking_to_energy_without_recombination_corr) then
       do k=1, s% nz
           adjusted_energy(k) = s% energy(k)
       end do
    else
     end if
 
    he_core_mass_1cent = 0.0d0
    he_core_mass_10cent = 0.0d0
    he_core_mass_30cent = 0.0d0
    !for MS stars = he core is 0, lambda calculated for whole star
    !for He stars = he core is whole star, lambda calculated for whole star
 
    he_core_radius_1cent = 0.0d0
    he_core_radius_10cent = 0.0d0
    he_core_radius_30cent = 0.0d0
 
    h1 = s% net_iso(ih1)
    he4 = s% net_iso(ihe4)
    have_30_value = .false.
    have_10_value = .false.
    have_1_value = .false.
    if (h1 /= 0 .and. he4 /= 0) then
      do k=1, s% nz
       if (.not. have_30_value) then
         if (s% xa(h1,k) <=  0.3d0 .and. &
           s% xa(he4,k) >= 0.1d0) then
           he_core_mass_30cent = s% m(k)
           he_core_radius_30cent = s% r(k)
           have_30_value = .true.
         end if
       end if
       if (.not. have_10_value) then
         if (s% xa(h1,k) <= 0.1d0 .and. &
           s% xa(he4,k) >= 0.1d0) then
           he_core_mass_10cent = s% m(k)
           he_core_radius_10cent = s% r(k)
           have_10_value = .true.
         end if
       end if
       if (.not. have_1_value) then
         if (s% xa(h1,k) <= 0.01d0 .and. &
           s% xa(he4,k) >= 0.1d0) then
           he_core_mass_1cent = s% m(k)
           he_core_radius_1cent = s% r(k)
           have_1_value = .true.
         end if
       end if
      end do
    end if
 
    lambda_CE_1cent = lambda_CE(s,adjusted_energy, he_core_mass_1cent)
    lambda_CE_10cent = lambda_CE(s,adjusted_energy, he_core_mass_10cent)
    lambda_CE_30cent = lambda_CE(s,adjusted_energy, he_core_mass_30cent)
 
    names(15) = 'lambda_CE_1cent'
    vals(15) = lambda_CE_1cent
    names(16) = 'lambda_CE_10cent'
    vals(16) = lambda_CE_10cent
    names(17) = 'lambda_CE_30cent'
    vals(17) = lambda_CE_30cent
 
    ! CO core:
    c12 = s% net_iso(ic12)
    o16 = s% net_iso(io16)
    XplusY_CO_core_mass_threshold = 0.1d0
 
    co_core_k = 0
    co_core_mass = 0.0d0
    co_core_radius = 0.0d0
    have_co_value = .false.
    if (c12 /= 0 .and. o16 /= 0) then
      do k=1, s% nz
       if (.not. have_co_value) then
         if (((s% xa(h1,k) + s% xa(he4,k))  <= XplusY_CO_core_mass_threshold) .and. &
           ((s% xa(c12,k) + s% xa(o16,k))  >= XplusY_CO_core_mass_threshold)) then
           call set_core_info(s, k, co_core_k, &
           co_core_mass, co_core_radius)
           have_co_value = .true.
         end if
       end if
      end do
    end if
 
    names(18) = 'co_core_mass'
    vals(18) = co_core_mass
    names(19) = 'co_core_radius'
    vals(19) = co_core_radius
 
    lambda_CE_pure_He_star_10cent = lambda_CE(s,adjusted_energy, co_core_mass)
    names(20) = 'lambda_CE_pure_He_star_10cent'
    vals(20) = lambda_CE_pure_He_star_10cent
 
 
    names(21) = 'he_core_mass_1cent'
    vals(21) = he_core_mass_1cent
    names(22) = 'he_core_mass_10cent'
    vals(22) = he_core_mass_10cent
    names(23) = 'he_core_mass_30cent'
    vals(23) = he_core_mass_30cent
    names(24) = 'he_core_radius_1cent'
    vals(24) = he_core_radius_1cent
    names(25) = 'he_core_radius_10cent'
    vals(25) = he_core_radius_10cent
    names(26) = 'he_core_radius_30cent'
    vals(26) = he_core_radius_30cent
 
 
    deallocate(adjusted_energy)
   end subroutine data_for_extra_history_columns
 
   real(dp) function lambda_CE(s, adjusted_energy, star_core_mass_CE)
       type (star_info), pointer :: s
       integer :: k
       real(dp) :: E_bind, E_bind_shell, star_core_mass_CE
       real(dp) :: adjusted_energy(:)
 
       if (s% m(1) <= (star_core_mass_CE)) then
          lambda_CE = 1d99 ! no envelope, so immediately have a "succesfull envelope ejection"
       else
          E_bind = 0.0d0
          E_bind_shell = 0.0d0
          do k=1, s% nz - 1
             if (s% m(k) > (star_core_mass_CE)) then !envelope is defined as everything above star_core_mass_CE.
                E_bind_shell = s% dm(k) * adjusted_energy(k) - (s% cgrav(k) * s% m(k+1) * s% dm(k))/(s% r(k+1))
                E_bind = E_bind+ E_bind_shell
             end if
          end do
          lambda_CE = - s% cgrav(1) * (s% m(1)) * ((s% m(1)) - star_core_mass_CE)/(E_bind * s% r(1))
       end if
    end function lambda_CE
 
    ! simpler version of the same function at star/private/report.f90
    subroutine set_core_info(s, k, &
          core_k, core_m, core_r)
       type (star_info), pointer :: s
       integer, intent(in) :: k
       integer, intent(out) :: core_k
       real(dp), intent(out) :: &
          core_m, core_r
 
       integer :: j, jm1, j00
       real(dp) :: dm1, d00, qm1, q00, core_q, &
          core_lgP, core_g, core_X, core_Y, core_edv_H, core_edv_He, &
          core_scale_height, core_dlnX_dr, core_dlnY_dr, core_dlnRho_dr
 
       include 'formats'
 
       if (k == 1) then
          core_q = 1d0
       else
          jm1 = maxloc(s% xa(:,k-1), dim=1)
          j00 = maxloc(s% xa(:,k), dim=1)
          qm1 = s% q(k-1) - 0.5d0*s% dq(k-1) ! center of k-1
          q00 = s% q(k) - 0.5d0*s% dq(k) ! center of k
          dm1 = s% xa(j00,k-1) - s% xa(jm1,k-1)
          d00 = s% xa(j00,k) - s% xa(jm1,k)
          if (dm1*d00 > 0d0) then
             write(*,2) 'bad args for set_core_info', k, dm1, d00
             call mesa_error(__FILE__,__LINE__)
             core_q = 0.5d0*(qm1 + q00)
          else if (dm1 == 0d0 .and. d00 == 0d0) then
             core_q = 0.5d0*(qm1 + q00)
          else if (dm1 == 0d0) then
             core_q = qm1
          else if (d00 == 0d0) then
             core_q = q00
          else
             core_q = find0(qm1, dm1, q00, d00)
          end if
       end if
 
       call get_info_at_q(s, core_q, &
          core_k, core_m, core_r)
 
    end subroutine set_core_info
 
 
    subroutine get_info_at_q(s, bdy_q, &
          kbdy, bdy_m, bdy_r)
 
       type (star_info), pointer :: s
       real(dp), intent(in) :: bdy_q
       integer, intent(out) :: kbdy
       real(dp), intent(out) :: &
          bdy_m, bdy_r
 
       real(dp) :: x, x0, x1, x2, alfa, beta, bdy_omega_crit
       integer :: k, ii, klo, khi
 
       include 'formats'
 
       bdy_m=0.0d0; bdy_r=0.0d0;
       kbdy = 0
 
       if (bdy_q <= 0.0d0) return
       k = k_for_q(s,bdy_q)
       if (k >= s% nz) then
          kbdy = s% nz
          return
       end if
       if (k <= 1) then
          bdy_m = s% star_mass
          bdy_r = s% r(1)/Rsun
          kbdy = 1
          return
       end if
 
       kbdy = k+1
 
       bdy_m = (s% M_center + s% xmstar*bdy_q)/Msun
 
       x = s% q(k-1) - bdy_q
       x0 = s% dq(k-1)/2.0d0
       x1 = s% dq(k)/2 + s% dq(k-1)
       x2 = s% dq(k+1)/2.0d0 + s% dq(k) + s% dq(k-1)
 
       alfa = max(0d0, min(1d0, (bdy_q - s% q(k+1))/s% dq(k)))
 
       bdy_r = pow( &
          interp2(s% r(k)*s% r(k)*s% r(k), s% r(k+1)*s% r(k+1)*s% r(k+1)),1d0/3d0)/Rsun
 
       contains
 
       real(dp) function interp2(f0, f1)
          real(dp), intent(in) :: f0, f1
          interp2 = alfa*f0 + (1.0d0-alfa)*f1
       end function interp2
 
    end subroutine get_info_at_q
 
 
 
 
 
   real(dp) function mass_conv_core(s)
       type (star_info), pointer :: s
       integer :: j, nz, k
       real(dp) :: dm_limit
       include 'formats'
       mass_conv_core = 0.0d0
       dm_limit = s% conv_core_gap_dq_limit*s% xmstar
       nz = s% nz
       do j = 1, s% n_conv_regions
          ! ignore possible small gap at center
          if (s% cz_bot_mass(j) <= s% m(nz) + dm_limit) then
             mass_conv_core = s% cz_top_mass(j)/Msun
             ! jump over small gaps
             do k = j+1, s% n_conv_regions
                if (s% cz_bot_mass(k) - s% cz_top_mass(k-1) >= dm_limit) exit
                mass_conv_core = s% cz_top_mass(k)/Msun
             end do
             exit
          end if
       end do
    end function mass_conv_core
 
 
   subroutine how_many_extra_profile_header_items(id, id_extra, num_cols)
       integer, intent(in) :: id, id_extra
       integer, intent(out) :: num_cols
       num_cols=3
   end subroutine how_many_extra_profile_header_items
 
   subroutine data_for_extra_profile_header_items( &
                   id, id_extra, num_extra_header_items, &
                   extra_header_item_names, extra_header_item_vals, ierr)
       use chem_def, only: chem_isos
       integer, intent(in) :: id, id_extra, num_extra_header_items
       character (len=*), pointer :: extra_header_item_names(:)
       real(dp), pointer :: extra_header_item_vals(:)
       type(star_info), pointer :: s
       integer, intent(out) :: ierr
       integer :: i
       real(dp) :: Initial_X, Initial_Y, Initial_Z, initial_m
       ierr = 0
       call star_ptr(id,s,ierr)
       if(ierr/=0) return
       !here is an example for adding an extra history header item
       !set num_cols=1 in how_many_extra_history_header_items and then unccomment these lines
       initial_X = 0._dp
       initial_Y = 0._dp
       initial_Z = 0._dp
       initial_m = 0._dp
       do i=1,s% species
          !write(*,*) chem_isos% name(s% chem_id(i)), s% xa(i,1)
          if( trim(chem_isos% name(s% chem_id(i))) == 'prot' .or. trim(chem_isos% name(s% chem_id(i))) == 'neut')then
             continue ! don't count these
          else if( trim(chem_isos% name(s% chem_id(i))) == 'h1' .or. trim(chem_isos% name(s% chem_id(i))) == 'h2' ) then
             initial_X = initial_X + s% xa(i,1)
          else if( trim(chem_isos% name(s% chem_id(i))) == 'he3' .or. trim(chem_isos% name(s% chem_id(i))) == 'he4' ) then
             initial_Y = initial_Y + s% xa(i,1)
          else
             initial_Z = initial_Z + s% xa(i,1)
          endif
       enddo
       initial_m = s% initial_mass
       extra_header_item_names(1) = 'initial_Z'
       extra_header_item_vals(1) = initial_Z
       extra_header_item_names(2) = 'initial_Y'
       extra_header_item_vals(2) =  initial_Y
       extra_header_item_names(3) = 'initial_m'
       extra_header_item_vals(3) =  initial_m
   end subroutine data_for_extra_profile_header_items
 
   integer function how_many_extra_profile_columns(id, id_extra)
     use star_def, only: star_info
     integer, intent(in) :: id, id_extra
     integer :: ierr
     type (star_info), pointer :: s
 
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
     how_many_extra_profile_columns = 0
 
   end function how_many_extra_profile_columns
 
 
   subroutine data_for_extra_profile_columns(id, id_extra, n, nz, names, vals, ierr)
     use star_def, only: star_info, maxlen_profile_column_name
     integer, intent(in) :: id, id_extra, n, nz
     character (len=maxlen_profile_column_name) :: names(n)
     real(dp) :: vals(nz,n)
     integer, intent(out) :: ierr
     type (star_info), pointer :: s
     integer :: k
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
   end subroutine data_for_extra_profile_columns
 
 
   integer function extras_finish_step(id)
     !use atm_lib, only: atm_option, atm_option_str
     !use kap_def, only: kap_lowT_option, lowT_AESOPUS
     integer, intent(in) :: id
     integer :: ierr, i
     real(dp) :: envelope_mass_fraction, L_He, L_tot, min_center_h1_for_diff, &
          critmass, feh, rot_full_off, rot_full_on, frac2
     real(dp), parameter :: huge_dt_limit = 3.15d16 ! ~1 Gyr
     real(dp), parameter :: new_varcontrol_target = 1d-3
     real(dp), parameter :: Zsol = 0.0142_dp
     type (star_info), pointer :: s
     logical :: diff_test1, diff_test2, diff_test3, is_ne_biggest
     character (len=strlen) :: photoname, stuff
 
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
     extras_finish_step = keep_going
     call store_extra_info(s)
 
     !if (s% center_h1 < 0.1) then
     !     write(*,'(g0)') "termination code: Central Abundance of H1 < 0.1, terminating from run_star_extras"        
     !  extras_finish_step = terminate
     !end if
   
      if (s% star_mass >= 4.0d4) then
         write(*,'(g0)') "termination code: Star mass >= 2.0d4, terminating from run_star_extras"     
         extras_finish_step = terminate
      end if
      
     if(s% x_logical_ctrl(2)) then ! this should only up for the 2 step of He star formation
       ! consistent with H-ZAMS definition from Aaron
       if (s% power_he_burn * Lsun / s% L(1) > 0.985)  extras_finish_step = terminate
       if (extras_finish_step == terminate) s% termination_code =t_extras_finish_step
     end if
 
     call check_TP(id) 
 
     ! TP-AGB
     if(TP_AGB_check .and.  have_done_TP)then
        TP_AGB_check = .false.
        late_AGB_check = .true.
        write(*,*) '++++++++++++++++++++++++++++++++++++++++++'
        write(*,*) 'now at TP-AGB phase, model number ', s% model_number
        !save a model and photo
        call star_write_model(id, 'TPAGB.mod', ierr)
        photoname = 'photos/TPAGB_photo'
        call star_save_for_restart(id, photoname, ierr)
        s% delta_lgTeff_limit = -1d0
        s% delta_lgTeff_hard_limit = -1d0
        s% delta_lgL_limit = -1d0
        s% delta_lgL_hard_limit = -1d0
        s% Blocker_scaling_factor = 2.0d0
        !s% varcontrol_target = 2.0d0*s% varcontrol_target
        write(*,*) ' varcontrol_target = ', s% varcontrol_target
        write(*,*) '++++++++++++++++++++++++++++++++++++++++++'
        if(s% x_logical_ctrl(1)) then
           call star_write_profile_info(id, "LOGS1/final_profile.data", ierr)
        endif
     endif
 
     ! late AGB
     if(late_AGB_check)then
        if (s% initial_mass < 8.0d0 .and. s% he_core_mass/s% star_mass > 0.9d0) then
           write(*,*) '++++++++++++++++++++++++++++++++++++++++++'
           write(*,*) 'now at late AGB phase, model number ', s% model_number
           write(*,*) '++++++++++++++++++++++++++++++++++++++++++'
           s% Blocker_scaling_factor = 5.0d0
           late_AGB_check=.false.
           post_AGB_check=.true.
        endif
       if(s% x_logical_ctrl(1)) then
              call star_write_profile_info(id, "LOGS1/final_profile.data", ierr)
       endif
     endif
 
     if(post_AGB_check)then
        if(s% Teff > 3.0d4)then
           write(*,*) '++++++++++++++++++++++++++++++++++++++++++'
           write(*,*) 'now at post AGB phase, model number ', s% model_number
           !save a model and photo
           call star_write_model(id, 'postAGB.mod', ierr)
           photoname = 'photos/pAGB_photo'
           call star_save_for_restart(id, photoname, ierr)
           if(s% job% extras_lpar(2))then
              s% max_abar_for_burning = -1.0d0
              write(*,*) 'turn off burning for post-AGB'
           endif
           !s% do_element_diffusion = .true.
           post_AGB_check = .false.
           pre_WD_check = .true.
           write(*,*) '++++++++++++++++++++++++++++++++++++++++++'
        endif
        if(s% x_logical_ctrl(1)) then
               call star_write_profile_info(id, "LOGS1/final_profile.data", ierr)
        endif
     endif
 
     ! pre-WD
     if(pre_WD_check)then
        if(s% Teff < 3.0d4 .and. s% L_surf < 1.0d0)then
           pre_WD_check = .false.
           s% do_wd_sedimentation_heating = .true.
           write(*,*) '++++++++++++++++++++++++++++++++++++++++++++++'
           write(*,*) 'now at WD phase, model number ', s% model_number
           !if(s% job% extras_lpar(2))then
           !   s% max_abar_for_burning = 199
           !   write(*,*) 'turn burning back on for WDs'
           !endif
           !s% do_element_diffusion = .true.
           !s% which_atm_option = 'WD_tau_25_tables'
           !call atm_option_str(atm_option(s% which_atm_option,ierr), stuff, ierr)
           write(*,*) '++++++++++++++++++++++++++++++++++++++++++++++'
        endif
        if(s% x_logical_ctrl(1)) then
               call star_write_profile_info(id, "LOGS1/final_profile.data", ierr)
        endif
     endif
 
     ! All stopping criteria are in run_binary_extras.f but we also use one here too for single star runs only
     ! define STOPPING CRITERION: stopping criterion for C burning exhaustion, massive stars.
     !if ((s% center_h1 < 1d-4) .and. (s% center_he4 < 5.0d-2) .and. (s% center_c12 < 5.0d-2)) then
     if(s% x_logical_ctrl(1)) then !check for central carbon depletion, only in case we run single stars.
       if ((s% center_h1 < 1d-4) .and. (s% center_he4 < 1.0d-4) .and. (s% center_c12 < 1.0d-2)) then
         write(*,'(g0)') "termination code: Single star depleted carbon, terminating from run_star_extras"
         extras_finish_step = terminate
       endif
       if ((s% center_h1 < 1d-6) .and. (s% initial_mass <= 0.9d0) .and. (s% star_age > 2.0d10) )then
           ! stopping criterion for TAMS, low mass stars.
          termination_code_str(t_xtra2) = &
            'termination code: Single, low-mass star depleted hydrogen, terminating from run_star_extras'
          s% termination_code = t_xtra2
          extras_finish_step = terminate
       endif
     endif
     min_center_h1_for_diff = 1d-10
     diff_test1 = abs(s% mass_conv_core - s% star_mass) < 1d-2 !fully convective
     diff_test2 = s% star_age > 5d10 !really old
     diff_test3 = .false. !s% center_h1 < min_center_h1_for_diff !past the main sequence
     if( diff_test1 .or. diff_test2 .or. diff_test3 )then
        s% diffusion_dt_limit = huge_dt_limit
     else
        s% diffusion_dt_limit = original_diffusion_dt_limit
     end if
 
     ! TP-AGB
     if(have_done_TP) then
        !termination_code_str(t_xtra2) = 'Reached TPAGB'
        !s% termination_code = t_xtra2
        !extras_finish_step = terminate
        write(*,'(g0)') 'Reached TPAGB'
     end if
   end function extras_finish_step
 
 
   subroutine extras_after_evolve(id, ierr)
     integer, intent(in) :: id
     integer, intent(out) :: ierr
     type (star_info), pointer :: s
     ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
     if(s% x_logical_ctrl(1)) then !check for central carbon depletion, only in case we run single stars.
       call star_write_profile_info(id, "LOGS1/final_profile.data", ierr)
     endif
   end subroutine extras_after_evolve
 
 
   subroutine alloc_extra_info(s)
     integer, parameter :: extra_info_alloc = 1
     type (star_info), pointer :: s
     call move_extra_info(s,extra_info_alloc)
   end subroutine alloc_extra_info
 
 
   subroutine unpack_extra_info(s)
     integer, parameter :: extra_info_get = 2
     type (star_info), pointer :: s
     call move_extra_info(s,extra_info_get)
   end subroutine unpack_extra_info
 
 
   subroutine store_extra_info(s)
     integer, parameter :: extra_info_put = 3
     type (star_info), pointer :: s
     call move_extra_info(s,extra_info_put)
   end subroutine store_extra_info
 
 
   subroutine move_extra_info(s,op)
     integer, parameter :: extra_info_alloc = 1
     integer, parameter :: extra_info_get = 2
     integer, parameter :: extra_info_put = 3
     type (star_info), pointer :: s
     integer, intent(in) :: op
 
     integer :: i, j, num_ints, num_dbls, ierr
 
     i = 0
     num_ints = i
 
     i = 0
     num_dbls = i
 
     if (op /= extra_info_alloc) return
     if (num_ints == 0 .and. num_dbls == 0) return
 
     ierr = 0
     call star_alloc_extras(s% id, num_ints, num_dbls, ierr)
     if (ierr /= 0) then
        write(*,*) 'failed in star_alloc_extras'
        write(*,*) 'alloc_extras num_ints', num_ints
        write(*,*) 'alloc_extras num_dbls', num_dbls
        stop 1
     end if
 
   contains
 
     subroutine move_dbl(dbl)
       real(dp) :: dbl
       i = i+1
       select case (op)
       case (extra_info_get)
          dbl = s% extra_work(i)
       case (extra_info_put)
          s% extra_work(i) = dbl
       end select
     end subroutine move_dbl
 
     subroutine move_int(int)
       integer :: int
       i = i+1
       select case (op)
       case (extra_info_get)
          int = s% extra_iwork(i)
       case (extra_info_put)
          s% extra_iwork(i) = int
       end select
     end subroutine move_int
 
     subroutine move_flg(flg)
       logical :: flg
       i = i+1
       select case (op)
       case (extra_info_get)
          flg = (s% extra_iwork(i) /= 0)
       case (extra_info_put)
          if (flg) then
             s% extra_iwork(i) = 1
          else
             s% extra_iwork(i) = 0
          end if
       end select
     end subroutine move_flg
 
   end subroutine move_extra_info
  
 subroutine loop_conv_layers(s,n_conv_regions_posydon, n_zones_of_region, bot_bdy, top_bdy, &
       cz_bot_mass_posydon, cz_bot_radius_posydon, cz_top_mass_posydon, cz_top_radius_posydon)
          type (star_info), pointer :: s
          ! integer, intent(out) :: ierr
 
          logical :: in_convective_region
          integer :: k, j, nz
          logical, parameter :: dbg = .false.
          integer, intent(out) :: n_conv_regions_posydon
          !integer :: max_num_mixing_regions
          !max_num_mixing_regions = 100
          !integer, intent(out), dimension (:), allocatable :: n_zones_of_region, bot_bdy, top_bdy
          !real(dp),intent(out), dimension (:), allocatable :: cz_bot_mass_posydon, cz_bot_radius_posydon
          !real(dp),intent(out), dimension (:), allocatable :: cz_top_mass_posydon, cz_top_radius_posydon
          integer :: min_zones_for_convective_tides
          integer ::  pot_n_zones_of_region, pot_bot_bdy, pot_top_bdy
          real(dp) :: pot_cz_bot_mass_posydon, pot_cz_bot_radius_posydon
          integer, intent(out), dimension (max_num_mixing_regions) :: n_zones_of_region, bot_bdy, top_bdy
          real(dp),intent(out), dimension (max_num_mixing_regions) :: cz_bot_mass_posydon
          real(dp),intent(out) :: cz_bot_radius_posydon(max_num_mixing_regions)
          real(dp),intent(out), dimension (max_num_mixing_regions) :: cz_top_mass_posydon, cz_top_radius_posydon
 
          include 'formats'
          !ierr = 0
          min_zones_for_convective_tides = 10
          nz = s% nz
          n_zones_of_region=0
          bot_bdy=0
          top_bdy=0
          cz_bot_mass_posydon=0.0_dp
          cz_bot_radius_posydon=0.0_dp
          cz_top_mass_posydon=0.0_dp
          cz_top_radius_posydon=0.0_dp
          n_conv_regions_posydon = 0_dp
          pot_cz_bot_mass_posydon = 0.0_dp
          pot_cz_bot_radius_posydon = 0.0_dp
          pot_bot_bdy = 0.0_dp
          pot_n_zones_of_region = 0
 
          in_convective_region = (s% mixing_type(nz) == convective_mixing)
          if (in_convective_region) then
             pot_cz_bot_mass_posydon = s% M_center
             pot_cz_bot_radius_posydon = 0.0_dp
             pot_bot_bdy = nz
          end if
  
          do k=nz-1, 2, -1
             if (in_convective_region) then
                if (s% mixing_type(k) /= convective_mixing) then ! top of convective region
                   pot_top_bdy = k
                   pot_n_zones_of_region = pot_bot_bdy - pot_top_bdy
                   if (pot_n_zones_of_region >= min_zones_for_convective_tides) then
                     if (n_conv_regions_posydon < max_num_mixing_regions) then
                       n_conv_regions_posydon = n_conv_regions_posydon + 1
                     end if
                     cz_top_mass_posydon(n_conv_regions_posydon) = &
                       s% M_center + (s% q(k) - s% cz_bdy_dq(k))*s% xmstar
                     cz_bot_mass_posydon(n_conv_regions_posydon) = pot_cz_bot_mass_posydon
                     cz_top_radius_posydon(n_conv_regions_posydon) = s% r(k)/Rsun
                     cz_bot_radius_posydon(n_conv_regions_posydon) = pot_cz_bot_radius_posydon
                     top_bdy(n_conv_regions_posydon) = pot_top_bdy
                     bot_bdy(n_conv_regions_posydon) = pot_bot_bdy
                     n_zones_of_region(n_conv_regions_posydon) = pot_n_zones_of_region
                   end if
                   in_convective_region = .false.
                end if
             else
                if (s% mixing_type(k) == convective_mixing) then ! bottom of convective region
                   pot_cz_bot_mass_posydon = &
                     s% M_center + (s% q(k) - s% cz_bdy_dq(k))*s% xmstar
                   pot_cz_bot_radius_posydon = s% r(k)/Rsun
                   pot_bot_bdy = k
                   in_convective_region = .true.
                end if
             end if
          end do
          if (in_convective_region) then
             pot_top_bdy = 1
             pot_n_zones_of_region = pot_bot_bdy - pot_top_bdy
             if (pot_n_zones_of_region >= min_zones_for_convective_tides) then
               if (n_conv_regions_posydon < max_num_mixing_regions) then
                 n_conv_regions_posydon = n_conv_regions_posydon + 1
               end if
               cz_top_mass_posydon(n_conv_regions_posydon) = s% mstar
               cz_top_radius_posydon(n_conv_regions_posydon) = s% r(1)/Rsun
               top_bdy(n_conv_regions_posydon) = 1
               cz_bot_mass_posydon(n_conv_regions_posydon) = pot_cz_bot_mass_posydon
               cz_bot_radius_posydon(n_conv_regions_posydon) = pot_cz_bot_radius_posydon
               bot_bdy(n_conv_regions_posydon) = pot_bot_bdy
               n_zones_of_region(n_conv_regions_posydon) = pot_n_zones_of_region
            end if
          end if
 
           !write(*,*)
           !write(*,2) 'set_mixing_info n_conv_regions_posydon', n_conv_regions_posydon
           !do j = 1, n_conv_regions_posydon
           !   write(*,2) 'conv region', j, cz_bot_mass_posydon(j)/Msun, cz_top_mass_posydon(j)/Msun
           !   write(*,2) 'conv region', j, cz_bot_radius_posydon(j), cz_top_radius_posydon(j)
           !end do
           !write(*,*)
       end subroutine loop_conv_layers
 
  
   subroutine other_set_mdot(id, L_phot, M_phot, R_phot, T_phot, X, Y, Z, wind, ierr)
      use chem_def
      use utils_lib
      integer, intent(in) :: id
      real(dp), intent(in) :: L_phot, M_phot, R_phot, T_phot, X, Y, Z ! photosphere values (cgs)
      real(dp), intent(out) :: wind
      integer, intent(out) :: ierr
      type (star_info), pointer :: s
      integer :: k, j, h1, he4, nz, base
      real(dp) :: max_ejection_mass, alfa, beta, &
           Zbase, Zsurf, w1, w2, T_high, T_low, L1, M1, R1, T1, &
           center_h1, center_he4, surface_h1, surface_he4, mdot, &
           full_off, full_on, cool_wind, hot_wind, divisor
      character (len=strlen) :: scheme
      logical :: using_wind_scheme_mdot
      real(dp), parameter :: Zsolar = 0.019d0 
  
      logical, parameter :: dbg = .false.
  
      include 'formats'
  
      ierr = 0
      call star_ptr(id, s, ierr)
      if(ierr/=0) return
  
      Zbase = s% kap_rq% Zbase
  
      L1 = L_phot
      M1 = M_phot
      T1 = T_phot
      R1 = R_phot
  
      h1 = s% net_iso(ih1)
      he4 = s% net_iso(ihe4)
      nz = s% nz
      wind = 0.0d0
      using_wind_scheme_mdot = .false.
  
      if (h1 > 0) then
         center_h1 = s% xa(h1,nz)
         surface_h1 = s% xa(h1,1)
      else
         center_h1 = 0.0d0
         surface_h1 = 0.0d0
      end if
      if (he4 > 0.0d0) then
         center_he4 = s% xa(he4,nz)
         surface_he4 = s% xa(he4,1)
      else
         center_he4 = 0.0d0
         surface_he4 = 0.0d0
      end if
  
      !massive stars
      if(s% initial_mass >= 10._dp)then
         scheme = s% hot_wind_scheme
         call eval_wind_for_scheme(scheme,wind)
         if (dbg) write(*,*) 'using hot_wind_scheme: "' // trim(scheme) // '"'
  
      !low-mass stars
      else
         if(T1 <= s% hot_wind_full_on_T)then
            !evaluate cool wind
            !RGB/TPAGB switch goes here
            if (have_done_TP) then
               scheme = s% cool_wind_AGB_scheme
               if (dbg) &
                    write(*,1) 'using cool_wind_AGB_scheme: "' // trim(scheme) // '"', &
                    center_h1, center_he4, s% RGB_to_AGB_wind_switch
  
            else
               scheme= s% cool_wind_RGB_scheme
               if (dbg) write(*,*) 'using cool_wind_RGB_scheme: "' // trim(scheme) // '"'
  
            endif
            call eval_wind_for_scheme(scheme, cool_wind)
         endif
  
         if(T1 >= s% cool_wind_full_on_T)then
            !evaluate hot wind
            scheme="Dutch"
            call eval_wind_for_scheme(scheme, hot_wind)
            if (dbg) write(*,*) 'using hot_wind_scheme: "' // trim(scheme) // '"'
  
         endif
  
         !now we have both hot and cool wind
  
         if(T1 < s% cool_wind_full_on_T) then
            wind = cool_wind
  
         elseif(T1 > s% hot_wind_full_on_T) then
            wind = hot_wind
  
         else
            !now combine the contributions of hot and cool winds
            divisor = s% hot_wind_full_on_T - s% cool_wind_full_on_T
            beta = min( (s% hot_wind_full_on_T - T1) / divisor, 1d0)
            alfa = 1d0 - beta
            wind = alfa*hot_wind + beta*cool_wind
         endif
      endif
  
    contains
  
      subroutine eval_wind_for_scheme(scheme,wind)
        character(len=strlen) :: scheme
        real(dp), intent(out) :: wind
        include 'formats'
  
        wind = 4d-13*(L1*R1/M1)/(Lsun*Rsun/Msun) ! in Msun/year
        if (dbg) write(*,1) 'wind', wind
        if (wind <= 0.0d0 .or. is_bad_num(wind)) then
           ierr = -1
           write(*,*) 'bad value for wind :', wind,L1,R1,M1
           if (dbg) stop 'debug: bad value for wind'
           if (s% stop_for_bad_nums) stop 'winds'
           return
        end if
        !X = surface_h1
        !Y = surface_he4
        !Z = Zbase ! previously 1-(X+Y)
        Zsurf = 1.0_dp - (X+Y)
  
        if (scheme == 'Dutch') then
           T_high = 11000.0d0
           T_low = 10000.0d0
           if (s% Dutch_scaling_factor == 0) then
              wind = 0.0d0
           else if (T1 <= T_low) then
              call eval_lowT_Dutch(wind)
           else if (T1 >= T_high) then
              call eval_highT_Dutch(wind)
           else ! transition
              call eval_lowT_Dutch(w1)
              call eval_highT_Dutch(w2)
              alfa = (T1 - T_low)/(T_high - T_low)
              wind = (1-alfa)*w1 + alfa*w2
           end if
           wind = s% Dutch_scaling_factor * wind
           if(dbg) write(*,1) 'Dutch_wind', wind
        else if (scheme == 'Reimers') then
           wind = wind * s% Reimers_scaling_factor
           if(dbg) write(*,1) 'Reimers_wind', wind
        else if (scheme == 'Vink') then
           call eval_Vink_wind(wind)
           wind = wind * s% Vink_scaling_factor
           if (dbg) write(*,1) 'Vink_wind', wind
        else if (scheme == 'Grafener') then
           call eval_Grafener_wind(wind)
           wind = wind !* s% Grafener_scaling_factor
           if (dbg) write(*,1) 'Grafener_wind', wind
        else if (scheme == 'Blocker') then
           call eval_blocker_wind(wind)
           if (dbg) write(*,1) 'Blocker_wind', wind
        else if (scheme == 'de Jager') then
           call eval_de_Jager_wind(wind)
           wind = s% de_Jager_scaling_factor * wind
           if (dbg) write(*,1) 'de_Jager_wind', wind
        else if (scheme == 'van Loon') then
           call eval_van_Loon_wind(wind)
           wind = s% van_Loon_scaling_factor * wind
           if (dbg) write(*,1) 'van_Loon_wind', wind
        else if (scheme == 'Nieuwenhuijzen') then
           call eval_Nieuwenhuijzen_wind(wind)
           wind = s% Nieuwenhuijzen_scaling_factor * wind
           if (dbg) write(*,1) 'Nieuwenhuijzen_wind', wind
        else
           ierr = -1
           write(*,*) 'unknown name for wind scheme : ' // trim(scheme)
           if (dbg) stop 'debug: bad value for wind scheme'
           return
        end if
  
        if(s% x_logical_ctrl(3)) then ! Belczynski+2010 LBV2 winds (eq. 8) with factor 1
          if ((s% center_h1 < 1.0d-4) ) then  ! postMS
              if ((s% L(1)/Lsun > 6.0d5) .and. &
                (1.0d-5 * s% r(1)/Rsun * pow((s% L(1)/Lsun),0.5d0) > 1.0d0)) then ! Humphreys-Davidson limit
                wind  = 1.0d-4
                if (dbg) write(*,1) 'LBV Belczynski+2010 wind', wind
              endif
          endif
       endif
  
      end subroutine eval_wind_for_scheme

      subroutine eval_Vink_wind(w)
         real(dp), intent(inout) :: w
         real(dp) :: logMdot

         !Winds (Vink 2018 VMS)
         logMdot = -9.13 + 2.1*log10(M1/Msun) + 0.74*log10(s% initial_Z/Zsolar)
         w = exp10(logMdot)

  
        if (dbg) write(*,*) 'vink wind', w
  
      end subroutine eval_Vink_wind
  
  
      subroutine eval_Grafener_wind(w)
        ! Grafener, G. & Hamann, W.-R. 2008, A&A 482, 945
        ! routine contributed by Nilou Afsari
        real(dp), intent(inout) :: w
        real(dp) :: w1, logMdot, gamma_edd, xsurf, beta, gammazero, lgZ
        xsurf = surface_h1
        gamma_edd = exp10(-4.813d0)*(1+xsurf)*(L1/Lsun)*(Msun/M1)
        lgZ = log10(Z/Zsolar)
        beta = 1.727d0 + 0.250d0*lgZ
        gammazero = 0.326d0 - 0.301d0*lgZ - 0.045d0*lgZ*lgZ
        logMdot = &
             + 10.046d0 &
             + beta*log10(gamma_edd - gammazero) &
             - 3.5d0*log10(T1) &
             + 0.42d0*log10(L1/Lsun) &
             - 0.45d0*xsurf
        w = exp10(logMdot)
        if (dbg) write(*,*) 'grafener wind', w
      end subroutine eval_Grafener_wind
  
  
      subroutine eval_blocker_wind(w)
        real(dp), intent(inout) :: w
        w = w * s% Blocker_scaling_factor * &
             4.83d-9 * pow(M1/Msun,-2.1d0) * pow(L1/Lsun,2.7d0)
        if (dbg) write(*,*) 'blocker wind', w
      end subroutine eval_blocker_wind
  
  
      subroutine eval_highT_Dutch(w)
        real(dp), intent(out) :: w
        include 'formats'
        if (surface_h1 < 0.4d0) then ! helium rich Wolf-Rayet star: Nugis & Lamers
           !write(*,*) 'Wolf-Rayet Star Winds'
           w = 1d-11 * pow(L1/Lsun,1.29d0) * pow(Y,1.7d0) * sqrt(Zsurf)
           if (dbg) write(*,1) 'Dutch_wind = Nugis & Lamers', log10(wind)
        else
           call eval_Vink_wind(w)
        end if
      end subroutine eval_highT_Dutch
  
  
      subroutine eval_lowT_Dutch(w)
        real(dp), intent(out) :: w
        include 'formats'
        if (s% Dutch_wind_lowT_scheme == 'de Jager') then
           call eval_de_Jager_wind(w)
           if (dbg) write(*,1) 'Dutch_wind = de Jager', safe_log10(wind), T1, T_low, T_high
        else if (s% Dutch_wind_lowT_scheme == 'van Loon') then
           call eval_van_Loon_wind(w)
           if (dbg) write(*,1) 'Dutch_wind = van Loon', safe_log10(wind), T1, T_low, T_high
        else if (s% Dutch_wind_lowT_scheme == 'Nieuwenhuijzen') then
           call eval_Nieuwenhuijzen_wind(w)
           if (dbg) write(*,1) 'Dutch_wind = Nieuwenhuijzen', safe_log10(wind), T1, T_low, T_high
        else
           write(*,*) 'unknown value for Dutch_wind_lowT_scheme ' // &
                trim(s% Dutch_wind_lowT_scheme)
           w = 0d0
        end if
      end subroutine eval_lowT_Dutch
  
  
      subroutine eval_de_Jager_wind(w)
        ! de Jager, C., Nieuwenhuijzen, H., & van der Hucht, K. A. 1988, A&AS, 72, 259.
        real(dp), intent(out) :: w
        real(dp) :: log10w
        include 'formats'
        log10w = 1.769d0*log10(L1/Lsun) - 1.676d0*log10(T1) - 8.158d0
        w = exp10(log10w)
        if (dbg) then
           write(*,1) 'de_Jager log10 wind', log10w
        end if
      end subroutine eval_de_Jager_wind
  
  
      subroutine eval_van_Loon_wind(w)
        ! van Loon et al. 2005, A&A, 438, 273
        real(dp), intent(out) :: w
        real(dp) :: log10w
        include 'formats'
        log10w = -5.65d0 + 1.05d0*log10(L1/(1d4*Lsun)) - 6.3d0*log10(T1/35d2)
        w = exp10(log10w)
      end subroutine eval_van_Loon_wind
  
  
      subroutine eval_Nieuwenhuijzen_wind(w)
        ! Nieuwenhuijzen, H.; de Jager, C. 1990, A&A, 231, 134 (eqn 2)
        real(dp), intent(out) :: w
        real(dp) :: log10w
        include 'formats'
        log10w = -14.02d0 + &
             1.24d0*log10(L1/Lsun) + &
             0.16d0*log10(M1/Msun) + &
             0.81d0*log10(R1/Rsun)
        w = exp10(log10w)
        if (dbg) then
           write(*,1) 'Nieuwenhuijzen log10 wind', log10w
        end if
      end subroutine eval_Nieuwenhuijzen_wind
  
    end subroutine other_set_mdot
 
   real(dp) function sige1(z,t,xgamma)
      ! Written by S.-C. Yoon, Oct. 10, 2003
      ! Electrical conductivity according to Spitzer 1962
      ! See also Wendell et al. 1987, ApJ 313:284
      real(dp), intent(in) :: z, t, xgamma
      real(dp) :: etan, xlambda,f
      if (t >= 4.2d5) then
         f = sqrt(4.2d5/t)
      else
         f = 1d0
      end if
      xlambda = sqrt(3d0*z*z*z)*pow(xgamma,-1.5d0)*f + 1d0
      etan = 3d11*z*log(xlambda)*pow(t,-1.5d0)             ! magnetic diffusivity
      etan = etan/(1d0-1.20487d0*exp(-1.0576d0*pow(z,0.347044d0))) ! correction: gammae
      sige1 = clight*clight/(4d0*pi*etan)                    ! sigma = c^2/(4pi*eta)
   end function sige1
 
 
   real(dp) function sige3(z,t,xgamma)
      ! writen by S.-C. YOON Oct. 10, 2003
      ! electrical conductivity in degenerate matter,
      ! according to Nandkumar & Pethick (1984)
      real(dp), intent(in) :: z, t, xgamma
      real(dp) :: rme, rm23, ctmp, xi
      rme = 8.5646d-23*t*t*t*xgamma*xgamma*xgamma/pow5(z)  ! rme = rho6/mue
      rm23 = pow(rme,2d0/3d0)
      ctmp = 1d0 + 1.018d0*rm23
      xi= sqrt(3.14159d0/3d0)*log(z)/3d0 + 2d0*log(1.32d0+2.33d0/sqrt(xgamma))/3d0-0.484d0*rm23/ctmp
      sige3 = 8.630d21*rme/(z*ctmp*xi)
   end function sige3
 
   integer function k_for_q(s, q)
          ! return k s.t. q(k) >= q > q(k)-dq(k)
          type (star_info), pointer :: s
          real(dp), intent(in) :: q
          integer :: k, nz
          nz = s% nz
          if (q >= 1.0d0) then
             k_for_q = 1; return
          else if (q <= s% q(nz)) then
             k_for_q = nz; return
          end if
          do k = 1, nz-1
             if (q > s% q(k+1)) then
                k_for_q = k; return
             end if
          end do
          k_for_q = nz
   end function k_for_q
 
 
   subroutine check_TP(id) ! check for AGB thermal pulse dredge up                                                                                                                       
             !logical, intent(in) :: burn_h, burn_he, burn_z
             !integer, intent(out) :: ierr
             !real(dp) :: h, hstep, h2, dr, dr2, dr_limit, r_limit, Bp1
             !logical :: have_done_TP
             !integer :: TP_state, TP_M_H_on, TP_M_H_min, TP_count
             integer, intent(in) :: id
             integer :: ierr
             real(dp) :: h1_czb_dm, h1_czb_mass_old
             type (star_info), pointer :: s        
             logical, parameter :: dbg = .false.
             integer, parameter :: max_DUP_counter = 200
             include 'formats'
             
             ierr = 0
     call star_ptr(id, s, ierr)
     if (ierr /= 0) return
 
             if (s% power_h_burn + s% power_he_burn < 0.5d0*s% power_nuc_burn) then
                if (dbg .and.  TP_state /= 0) then
                   write(*,*) 'advanced burning: change to TP_state = 0'
                   write(*,*)
                end if
                TP_state = 0
             else if (s% he_core_mass > s% co_core_mass + 0.1d0) then
                if (dbg .and. TP_state /= 0) then
                   write(*,*) 'not yet: change to TP_state = 0'
                   write(*,1) 's% he_core_mass', s% he_core_mass
                   write(*,1) 's% co_core_mass', s% co_core_mass
                   write(*,1) 'h1 - co_core_mass', s% he_core_mass - s% co_core_mass
                   write(*,*)
                end if
                TP_state = 0
             else if (TP_state == 0) then ! not in TP                                                                                                                                                                                                                                                                                                                   
                       if (s% power_he_burn > s% power_h_burn) then ! starting TP                                                                                                                                                                                                                                                                                                 
                   TP_state = 1
                   TP_M_H_on = s% h1_czb_mass
                   TP_M_H_min = s% h1_czb_mass
                   if (dbg) then
                      write(*,*) 'change to TP_state = 1'
                      write(*,1) 'TP_M_H_on',  TP_M_H_on
                      write(*,*)
                   end if
                end if
             else
                h1_czb_dm = s% h1_czb_mass*1d-6
                if (TP_state == 1) then ! early part of TP                                                                                                                                                                                                                                                                                                              
                   if (s% h1_czb_mass <  TP_M_H_on - h1_czb_dm) then
                      if (dbg) then
                         write(*,*) 'change to TP_state = 2'
                         write(*,1) 's% TP_M_H_on', TP_M_H_on
                         write(*,1) 'h1_czb_dm', h1_czb_dm
                         write(*,1) 's% TP_M_H_on - h1_czb_dm',  TP_M_H_on - h1_czb_dm
                         write(*,1) 'h1_czb_mass', s% h1_czb_mass
                         write(*,1) '(s% TP_M_H_on - h1_czb_dm) - h1_czb_mass', &
                            (TP_M_H_on - h1_czb_dm) - s% h1_czb_mass
                                         write(*,*)
                      end if
                                   TP_state = 2
                                   TP_count = 0
                      TP_M_H_min = s% h1_czb_mass
                      have_done_TP = .true.
                      ! MANOS to replace s% h1_czb_mass_old which does not exist any more in the new MESA version
                      h1_czb_mass_old = s% h1_czb_mass*Msun
                   else if (s% power_h_burn > s% power_he_burn) then ! no dredge up                                                                                                                                                                                                                                                                                       
                      if (dbg) write(*,*) 'change to TP_state = 0: no dredge up this time'
                      TP_state = 0
                   end if
                else if (TP_state == 2) then ! dredge up part of TP                                                                                                                                                                                                                                                                                                     
                   if (s% h1_czb_mass < TP_M_H_min)  TP_M_H_min = s% h1_czb_mass
                   ! h1_czb_mass_old = s% h1_czb_mass_old*Msun ! MANOS commented
                   if (dbg) then
                      write(*,1) '(h1_czb_mass - h1_czb_mass_old)/Msun', &
                         (s% h1_czb_mass - h1_czb_mass_old)/Msun
                      write(*,1) 'h1_czb_dm/Msun', h1_czb_dm/Msun
                      write(*,*)
                   end if
                   if (s% h1_czb_mass > h1_czb_mass_old + h1_czb_dm .or. &
                         s% power_h_burn > s% power_he_burn) then
                      TP_count = TP_count + 1
                      if (dbg) write(*,2) '++ TP_count',  TP_count, &
                            s% h1_czb_mass - (h1_czb_mass_old + h1_czb_dm), &
                           s%  h1_czb_mass,  h1_czb_mass_old + h1_czb_dm, &
                            h1_czb_mass_old, h1_czb_dm
                   else if (s% h1_czb_mass < h1_czb_mass_old - h1_czb_dm) then
                      TP_count = max(0, TP_count - 1)
                      if (dbg) write(*,3) '-- TP_count',  TP_count,  TP_state
                   end if
                   if ( TP_count >  max_DUP_counter) then
                      if (dbg) write(*,*) 'change to TP_state = 0'
                      TP_state = 0
                   end if
                end if
                if (TP_state == 2) then
                   !f_below = f_below*s% overshoot_below_noburn_shell_factor
                   !f0_below = f0_below*s% overshoot_below_noburn_shell_factor
                end  if
             end if
          end subroutine check_TP
 
         !Function Accretion of mass as in Haemmerlé et al.(2016)
          subroutine my_adjust_mdot(id, ierr) 
            use star_def
            integer, intent(in) :: id
            integer, intent(out) :: ierr
            real(dp) :: f, w, log_mdot_out, mdot_out, m2r
    
            type (star_info), pointer :: s
    
            ierr = 0
            call star_ptr(id, s, ierr)
            if (ierr /= 0) then
              write(*,*) 'failed in star_ptr'
               return
            end if
         
            s% mstar_dot = 0.0d0
            w = 0.0d0
            s% explicit_mstar_dot = s% mstar_dot
            ! Mass to reach 
            m2r = 2.0d4
            if (s% x_logical_ctrl(4)) then
              if (s% star_mass <= 5.0d0) then
              
                f = 1.0/3.0
                
              else if (s% star_mass > 5.0 .and. s% star_mass <= m2r) then
              
                f = 1.0/11.0
              end if

              log_mdot_out = -5.28 + s% log_surface_luminosity *(0.752 - 0.0278*s% log_surface_luminosity) ![M_sun/yr]
              mdot_out = 10**(log_mdot_out) * (Msun/secyer) * 10  ![gr/s]  10 for high accretion
    
              w = f/(1-f)*mdot_out 
                 
            endif
            
            if (s% star_mass <= m2r ) then
              s% mstar_dot = (s% mstar_dot + w)
              s% explicit_mstar_dot = s% mstar_dot 
              !write(*,*) 'M<1e4  mstar_dot= ', s% mstar_dot
             
            
            else if(s% star_mass > m2r) then 
              s% mstar_dot = 0.0d0
              s% x_logical_ctrl(4) = .false.
              s% use_other_adjust_mdot = .false. !Turn off the  accretion
              s% use_other_wind = .false.  !No winds during accretion
              write(*,*) 'use_other_wind =.false. '
              s% Dutch_scaling_factor = 1.0d0
              s% Blocker_scaling_factor = 0.2d0
              s% Reimers_scaling_factor = 0.1d0
              !write(*,*) 'Dutch_scaling_factor= ', s% Dutch_scaling_factor
              !write(*,*) 'Blocker_scaling_factor= ', s% Blocker_scaling_factor 
              !write(*,*) 'Reimers_scaling_factor= ',s% Reimers_scaling_factor 

            end if
    
      end subroutine my_adjust_mdot
 
 end module run_star_extras
 