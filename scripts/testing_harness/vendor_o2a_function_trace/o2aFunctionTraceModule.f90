module o2aFunctionTraceModule

  use, intrinsic :: ieee_arithmetic

  implicit none

  logical, save :: initialized = .false.
  logical, save :: trace_enabled = .false.
  integer, parameter :: max_trace_wavelengths = 16
  integer, parameter :: path_length = 1024
  real(8), parameter :: wavelength_match_tolerance_nm = 1.5d-2
  real(8), parameter :: wavelength_support_tolerance_nm = 1.25d0

  character(len=path_length), save :: trace_root = ''
  integer, save :: trace_wavelength_count = 0
  real(8), save :: trace_wavelengths_nm(max_trace_wavelengths) = 0.0d0
  real(8), save :: active_wavelength_nm = -1.0d0

  integer, save :: line_catalog_unit = -1
  integer, save :: strong_state_unit = -1
  integer, save :: spectroscopy_weak_unit = -1
  integer, save :: spectroscopy_strong_unit = -1
  integer, save :: weak_line_contributors_unit = -1
  integer, save :: sublayer_optics_raw_unit = -1
  integer, save :: adaptive_grid_unit = -1
  integer, save :: kernel_samples_unit = -1
  integer, save :: transport_samples_unit = -1
  integer, save :: transport_summary_unit = -1
  integer, save :: fourier_terms_unit = -1
  integer, save :: transport_layers_unit = -1
  logical, save :: line_catalog_frozen = .false.
  integer, save :: last_line_catalog_source_index = 0

  integer, save :: stored_interval_count = 0
  real(8), allocatable, save :: stored_interval_start_nm(:)
  real(8), allocatable, save :: stored_interval_end_nm(:)
  real(8), allocatable, save :: stored_interval_source_center_nm(:)
  integer, allocatable, save :: stored_interval_division_count(:)
  logical, allocatable, save :: stored_interval_is_strong(:)

contains

  subroutine o2a_trace_init()
    character(len=path_length) :: env_value
    integer :: env_length
    integer :: env_status

    if (initialized) return
    initialized = .true.

    call get_environment_variable('ZDISAMAR_O2A_TRACE_ROOT', env_value, length=env_length, status=env_status)
    if (env_status /= 0 .or. env_length <= 0) return

    trace_root = trim(env_value(1:env_length))
    call get_environment_variable('ZDISAMAR_O2A_TRACE_WAVELENGTHS_NM', env_value, length=env_length, status=env_status)
    if (env_status == 0 .and. env_length > 0) then
      call parse_wavelength_list(trim(env_value(1:env_length)))
    end if
    if (trace_wavelength_count <= 0) then
      trace_wavelength_count = 1
      trace_wavelengths_nm(1) = 761.75d0
    end if

    call open_trace_file(line_catalog_unit, 'line_catalog.csv', &
      'source_row_index,gas_index,isotope_number,center_wavelength_nm,center_wavenumber_cm1,line_strength_cm2_per_molecule,air_half_width_nm,temperature_exponent,lower_state_energy_cm1,pressure_shift_nm,line_mixing_coefficient,branch_ic1,branch_ic2,rotational_nf')
    call open_trace_file(strong_state_unit, 'strong_state.csv', &
      'pressure_hpa,temperature_k,strong_index,center_wavelength_nm,center_wavenumber_cm1,sig_moy_cm1,population_t,dipole_t,mod_sig_cm1,half_width_cm1_at_t,line_mixing_coefficient')
    call open_trace_file(spectroscopy_weak_unit, 'spectroscopy_weak_raw.csv', &
      'pressure_hpa,temperature_k,wavelength_nm,weak_sigma_cm2_per_molecule')
    call open_trace_file(spectroscopy_strong_unit, 'spectroscopy_strong_raw.csv', &
      'pressure_hpa,temperature_k,wavelength_nm,strong_sigma_cm2_per_molecule,line_mixing_sigma_cm2_per_molecule')
    call open_trace_file(weak_line_contributors_unit, 'weak_line_contributors.csv', &
      'pressure_hpa,temperature_k,wavelength_nm,sample_wavelength_nm,source_row_index,contribution_kind,gas_index,isotope_number,center_wavelength_nm,center_wavenumber_cm1,shifted_center_wavenumber_cm1,line_strength_cm2_per_molecule,air_half_width_nm,temperature_exponent,lower_state_energy_cm1,pressure_shift_nm,line_mixing_coefficient,branch_ic1,branch_ic2,rotational_nf,matched_strong_index,weak_line_sigma_cm2_per_molecule')
    call open_trace_file(sublayer_optics_raw_unit, 'sublayer_optics_raw.csv', &
      'actual_wavelength_nm,wavelength_nm,global_sublayer_index,interval_index_1based,pressure_hpa,temperature_k,number_density_cm3,oxygen_number_density_cm3,line_cross_section_cm2_per_molecule,line_mixing_cross_section_cm2_per_molecule,cia_sigma_cm5_per_molecule2,gas_absorption_optical_depth,gas_scattering_optical_depth,cia_optical_depth,path_length_cm,aerosol_optical_depth,aerosol_scattering_optical_depth,cloud_optical_depth,cloud_scattering_optical_depth,total_scattering_optical_depth,total_optical_depth,combined_phase_coef_0,combined_phase_coef_1,combined_phase_coef_2,combined_phase_coef_3,combined_phase_coef_10,combined_phase_coef_20,combined_phase_coef_39')
    call open_trace_file(adaptive_grid_unit, 'adaptive_grid.csv', &
      'nominal_wavelength_nm,interval_kind,source_center_wavelength_nm,interval_start_nm,interval_end_nm,division_count')
    call open_trace_file(kernel_samples_unit, 'kernel_samples.csv', &
      'nominal_wavelength_nm,sample_index,sample_wavelength_nm,weight')
    call open_trace_file(transport_samples_unit, 'transport_samples.csv', &
      'nominal_wavelength_nm,sample_index,sample_wavelength_nm,radiance,irradiance,weight')
    call open_trace_file(transport_summary_unit, 'transport_summary.csv', &
      'nominal_wavelength_nm,final_radiance,final_irradiance,final_reflectance')
    call open_trace_file(fourier_terms_unit, 'fourier_terms.csv', &
      'nominal_wavelength_nm,sample_wavelength_nm,fourier_index,refl_fc,source_refl_fc,surface_refl_fc,surface_e_view,surface_u_view_solar,fourier_weight,weighted_refl')
    call open_trace_file(transport_layers_unit, 'transport_layers.csv', &
      'nominal_wavelength_nm,sample_wavelength_nm,layer_index,optical_depth,scattering_optical_depth,single_scatter_albedo,phase_coef_0,phase_coef_1,phase_coef_2,phase_coef_3,phase_coef_10,phase_coef_20,phase_coef_39')

    trace_enabled = .true.
  end subroutine o2a_trace_init

  subroutine o2a_trace_line_catalog_row(source_row_index, gas_index, isotope_number, sig_cm1, strength, gamma_cm1, lower_state_energy_cm1, beta, delta_cm1, ic1, ic2, nf)
    integer, intent(in) :: source_row_index
    integer, intent(in) :: gas_index
    integer, intent(in) :: isotope_number
    integer, intent(in) :: ic1
    integer, intent(in) :: ic2
    integer, intent(in) :: nf
    real(8), intent(in) :: sig_cm1
    real(8), intent(in) :: strength
    real(8), intent(in) :: gamma_cm1
    real(8), intent(in) :: lower_state_energy_cm1
    real(8), intent(in) :: beta
    real(8), intent(in) :: delta_cm1

    real(8) :: center_wavelength_nm
    real(8) :: air_half_width_nm
    real(8) :: pressure_shift_nm
    real(8) :: line_mixing_coefficient
    real(8) :: nan_value
    logical :: valid_branch_value

    call o2a_trace_init()
    if (.not. trace_enabled) return
    if (line_catalog_frozen) return
    if (source_row_index <= last_line_catalog_source_index) then
      line_catalog_frozen = .true.
      return
    end if
    last_line_catalog_source_index = source_row_index

    nan_value = ieee_value(0.0d0, ieee_quiet_nan)
    center_wavelength_nm = 1.0d7 / max(sig_cm1, 1.0d0)
    air_half_width_nm = gamma_cm1 * 1.0d7 / max(sig_cm1 * sig_cm1, 1.0d0)
    pressure_shift_nm = -delta_cm1 * 1.0d7 / max(sig_cm1 * sig_cm1, 1.0d0)
    line_mixing_coefficient = min(0.15d0, abs(delta_cm1) / max(abs(gamma_cm1), 1.0d-6))

    valid_branch_value = ic1 >= 0 .and. ic1 <= 99
    write(line_catalog_unit, '(*(g0,:,","))') source_row_index, gas_index, isotope_number, center_wavelength_nm, sig_cm1, &
      strength, air_half_width_nm, beta, lower_state_energy_cm1, pressure_shift_nm, line_mixing_coefficient, &
      merge(dble(ic1), nan_value, valid_branch_value), &
      merge(dble(ic2), nan_value, ic2 >= 0 .and. ic2 <= 99), &
      merge(dble(nf), nan_value, nf >= 0 .and. nf <= 99)
    flush(line_catalog_unit)
  end subroutine o2a_trace_line_catalog_row

  subroutine o2a_trace_convtp_state(temperature_k, pressure_atm, sig_moy_cm1, nlines, sig_lines_cm1, popu_t, dipo_t, mod_sig_cm1, hwt_cm1, yt)
    real(8), intent(in) :: temperature_k
    real(8), intent(in) :: pressure_atm
    real(8), intent(in) :: sig_moy_cm1
    integer, intent(in) :: nlines
    real(8), intent(in) :: sig_lines_cm1(nlines)
    real(8), intent(in) :: popu_t(nlines)
    real(8), intent(in) :: dipo_t(nlines)
    real(8), intent(in) :: mod_sig_cm1(nlines)
    real(8), intent(in) :: hwt_cm1(nlines)
    real(8), intent(in) :: yt(nlines)
    integer :: line_index
    real(8) :: pressure_hpa

    call o2a_trace_init()
    if (.not. trace_enabled) return

    pressure_hpa = pressure_atm * 1013.25d0
    do line_index = 1, nlines
      write(strong_state_unit, '(*(g0,:,","))') pressure_hpa, temperature_k, line_index - 1, 1.0d7 / max(sig_lines_cm1(line_index), 1.0d0), &
        sig_lines_cm1(line_index), sig_moy_cm1, popu_t(line_index), dipo_t(line_index), mod_sig_cm1(line_index), &
        hwt_cm1(line_index), yt(line_index)
    end do
    flush(strong_state_unit)
  end subroutine o2a_trace_convtp_state

  subroutine o2a_trace_weak_spectroscopy(temperature_k, pressure_atm, nvalues, wavelengths_nm, abs_xsec)
    real(8), intent(in) :: temperature_k
    real(8), intent(in) :: pressure_atm
    integer, intent(in) :: nvalues
    real(8), intent(in) :: wavelengths_nm(nvalues)
    real(8), intent(in) :: abs_xsec(nvalues)
    integer :: trace_index
    integer :: nearest_index(1)
    real(8) :: pressure_hpa

    call o2a_trace_init()
    if (.not. trace_enabled) return

    pressure_hpa = pressure_atm * 1013.25d0
    do trace_index = 1, trace_wavelength_count
      nearest_index = minloc(abs(wavelengths_nm(:) - trace_wavelengths_nm(trace_index)))
      write(spectroscopy_weak_unit, '(*(g0,:,","))') pressure_hpa, temperature_k, trace_wavelengths_nm(trace_index), abs_xsec(nearest_index(1))
    end do
    flush(spectroscopy_weak_unit)
  end subroutine o2a_trace_weak_spectroscopy

  subroutine o2a_trace_weak_line_contributor(temperature_k, pressure_atm, nominal_wavelength_nm, sample_wavelength_nm, source_row_index, gas_index, isotope_number, sig_cm1, shifted_sig_cm1, strength, gamma_cm1, beta, lower_state_energy_cm1, delta_cm1, weak_sigma)
    real(8), intent(in) :: temperature_k
    real(8), intent(in) :: pressure_atm
    real(8), intent(in) :: nominal_wavelength_nm
    real(8), intent(in) :: sample_wavelength_nm
    integer, intent(in) :: source_row_index
    integer, intent(in) :: gas_index
    integer, intent(in) :: isotope_number
    real(8), intent(in) :: sig_cm1
    real(8), intent(in) :: shifted_sig_cm1
    real(8), intent(in) :: strength
    real(8), intent(in) :: gamma_cm1
    real(8), intent(in) :: beta
    real(8), intent(in) :: lower_state_energy_cm1
    real(8), intent(in) :: delta_cm1
    real(8), intent(in) :: weak_sigma

    real(8) :: pressure_hpa
    real(8) :: center_wavelength_nm
    real(8) :: air_half_width_nm
    real(8) :: pressure_shift_nm
    real(8) :: line_mixing_coefficient
    real(8) :: nan_value

    call o2a_trace_init()
    if (.not. trace_enabled) return

    pressure_hpa = pressure_atm * 1013.25d0
    nan_value = ieee_value(0.0d0, ieee_quiet_nan)
    center_wavelength_nm = 1.0d7 / max(sig_cm1, 1.0d0)
    air_half_width_nm = gamma_cm1 * 1.0d7 / max(sig_cm1 * sig_cm1, 1.0d0)
    pressure_shift_nm = -delta_cm1 * 1.0d7 / max(sig_cm1 * sig_cm1, 1.0d0)
    line_mixing_coefficient = min(0.15d0, abs(delta_cm1) / max(abs(gamma_cm1), 1.0d-6))

    write(weak_line_contributors_unit, '(*(g0,:,","))') pressure_hpa, temperature_k, nominal_wavelength_nm, sample_wavelength_nm, &
      source_row_index, 'weak_included', gas_index, isotope_number, center_wavelength_nm, sig_cm1, shifted_sig_cm1, strength, &
      air_half_width_nm, beta, lower_state_energy_cm1, pressure_shift_nm, line_mixing_coefficient, &
      nan_value, nan_value, nan_value, nan_value, weak_sigma
    flush(weak_line_contributors_unit)
  end subroutine o2a_trace_weak_line_contributor

  subroutine o2a_trace_strong_spectroscopy(temperature_k, pressure_atm, nvalues, wave_numbers_cm1, xsec_strong, xsec_lm)
    real(8), intent(in) :: temperature_k
    real(8), intent(in) :: pressure_atm
    integer, intent(in) :: nvalues
    real(8), intent(in) :: wave_numbers_cm1(nvalues)
    real(8), intent(in) :: xsec_strong(nvalues)
    real(8), intent(in) :: xsec_lm(nvalues)
    integer :: trace_index
    integer :: nearest_index(1)
    real(8) :: wavelengths_nm(nvalues)
    real(8) :: pressure_hpa

    call o2a_trace_init()
    if (.not. trace_enabled) return

    wavelengths_nm(:) = 1.0d7 / max(wave_numbers_cm1(:), 1.0d0)
    pressure_hpa = pressure_atm * 1013.25d0
    do trace_index = 1, trace_wavelength_count
      nearest_index = minloc(abs(wavelengths_nm(:) - trace_wavelengths_nm(trace_index)))
      write(spectroscopy_strong_unit, '(*(g0,:,","))') pressure_hpa, temperature_k, trace_wavelengths_nm(trace_index), &
        xsec_strong(nearest_index(1)), xsec_lm(nearest_index(1))
    end do
    flush(spectroscopy_strong_unit)
  end subroutine o2a_trace_strong_spectroscopy

  subroutine o2a_trace_store_intervals(interval_count, interval_boundaries, interval_is_strong, interval_source_center, interval_divisions)
    integer, intent(in) :: interval_count
    real(8), intent(in) :: interval_boundaries(0:interval_count)
    logical, intent(in) :: interval_is_strong(interval_count)
    real(8), intent(in) :: interval_source_center(interval_count)
    integer, intent(in) :: interval_divisions(interval_count)
    integer :: interval_index

    call o2a_trace_init()
    if (.not. trace_enabled) return

    if (allocated(stored_interval_start_nm)) deallocate(stored_interval_start_nm)
    if (allocated(stored_interval_end_nm)) deallocate(stored_interval_end_nm)
    if (allocated(stored_interval_source_center_nm)) deallocate(stored_interval_source_center_nm)
    if (allocated(stored_interval_division_count)) deallocate(stored_interval_division_count)
    if (allocated(stored_interval_is_strong)) deallocate(stored_interval_is_strong)

    if (interval_count <= 0) return

    allocate(stored_interval_start_nm(interval_count))
    allocate(stored_interval_end_nm(interval_count))
    allocate(stored_interval_source_center_nm(interval_count))
    allocate(stored_interval_division_count(interval_count))
    allocate(stored_interval_is_strong(interval_count))

    stored_interval_count = interval_count
    do interval_index = 1, interval_count
      stored_interval_start_nm(interval_index) = interval_boundaries(interval_index - 1)
      stored_interval_end_nm(interval_index) = interval_boundaries(interval_index)
      stored_interval_source_center_nm(interval_index) = interval_source_center(interval_index)
      stored_interval_division_count(interval_index) = interval_divisions(interval_index)
      stored_interval_is_strong(interval_index) = interval_is_strong(interval_index)
    end do
  end subroutine o2a_trace_store_intervals

  subroutine o2a_trace_emit_kernel_and_transport(nominal_wavelength_nm, start_index, end_index, wavelengths_nm, weights, radiance_hr, irradiance_hr)
    real(8), intent(in) :: nominal_wavelength_nm
    integer, intent(in) :: start_index
    integer, intent(in) :: end_index
    real(8), intent(in) :: wavelengths_nm(:)
    real(8), intent(in) :: weights(:)
    real(8), intent(in) :: radiance_hr(:)
    real(8), intent(in) :: irradiance_hr(:)
    integer :: trace_match_index
    integer :: sample_index
    integer :: interval_index
    logical, allocatable :: interval_seen(:)
    character(len=32) :: interval_kind
    real(8) :: nan_value
    real(8) :: traced_wavelength_nm

    call o2a_trace_init()
    if (.not. trace_enabled) return

    trace_match_index = find_trace_wavelength_index(nominal_wavelength_nm)
    if (trace_match_index <= 0) return
    traced_wavelength_nm = trace_wavelengths_nm(trace_match_index)

    if (stored_interval_count > 0) then
      allocate(interval_seen(stored_interval_count))
      interval_seen(:) = .false.
      do sample_index = start_index, end_index
        do interval_index = 1, stored_interval_count
          if (wavelengths_nm(sample_index) < stored_interval_start_nm(interval_index)) cycle
          if (wavelengths_nm(sample_index) > stored_interval_end_nm(interval_index)) cycle
          if (interval_seen(interval_index)) exit
          interval_seen(interval_index) = .true.
          nan_value = ieee_value(0.0d0, ieee_quiet_nan)
          if (stored_interval_is_strong(interval_index)) then
            interval_kind = 'strong_refinement'
          else
            interval_kind = 'uniform'
          end if
          write(adaptive_grid_unit, '(*(g0,:,","))') traced_wavelength_nm, &
            trim(interval_kind), &
            merge(stored_interval_source_center_nm(interval_index), nan_value, stored_interval_is_strong(interval_index)), &
            stored_interval_start_nm(interval_index), stored_interval_end_nm(interval_index), stored_interval_division_count(interval_index)
          exit
        end do
      end do
      deallocate(interval_seen)
      flush(adaptive_grid_unit)
    end if

    do sample_index = start_index, end_index
      write(kernel_samples_unit, '(*(g0,:,","))') traced_wavelength_nm, sample_index - start_index, wavelengths_nm(sample_index), weights(sample_index)
      write(transport_samples_unit, '(*(g0,:,","))') traced_wavelength_nm, sample_index - start_index, wavelengths_nm(sample_index), &
        radiance_hr(sample_index), irradiance_hr(sample_index), weights(sample_index)
    end do
    flush(kernel_samples_unit)
    flush(transport_samples_unit)
  end subroutine o2a_trace_emit_kernel_and_transport

  subroutine o2a_trace_transport_summary(nominal_wavelength_nm, radiance, irradiance, reflectance)
    real(8), intent(in) :: nominal_wavelength_nm
    real(8), intent(in) :: radiance
    real(8), intent(in) :: irradiance
    real(8), intent(in) :: reflectance

    integer :: trace_match_index

    call o2a_trace_init()
    if (.not. trace_enabled) return
    trace_match_index = find_trace_wavelength_index(nominal_wavelength_nm)
    if (trace_match_index <= 0) return

    write(transport_summary_unit, '(*(g0,:,","))') trace_wavelengths_nm(trace_match_index), radiance, irradiance, reflectance
    flush(transport_summary_unit)
  end subroutine o2a_trace_transport_summary

  subroutine o2a_trace_sublayer_optics(wavelength_nm, global_sublayer_index, interval_index_1based, pressure_hpa, temperature_k, number_density_cm3, oxygen_number_density_cm3, line_cross_section_cm2_per_molecule, cia_sigma_cm5_per_molecule2, gas_absorption_optical_depth, gas_scattering_optical_depth, cia_optical_depth, path_length_cm, aerosol_optical_depth, aerosol_scattering_optical_depth, cloud_optical_depth, cloud_scattering_optical_depth, total_scattering_optical_depth, total_optical_depth, combined_phase_coef_0, combined_phase_coef_1, combined_phase_coef_2, combined_phase_coef_3, combined_phase_coef_10, combined_phase_coef_20, combined_phase_coef_39)
    real(8), intent(in) :: wavelength_nm
    integer, intent(in) :: global_sublayer_index
    integer, intent(in) :: interval_index_1based
    real(8), intent(in) :: pressure_hpa
    real(8), intent(in) :: temperature_k
    real(8), intent(in) :: number_density_cm3
    real(8), intent(in) :: oxygen_number_density_cm3
    real(8), intent(in) :: line_cross_section_cm2_per_molecule
    real(8), intent(in) :: cia_sigma_cm5_per_molecule2
    real(8), intent(in) :: gas_absorption_optical_depth
    real(8), intent(in) :: gas_scattering_optical_depth
    real(8), intent(in) :: cia_optical_depth
    real(8), intent(in) :: path_length_cm
    real(8), intent(in) :: aerosol_optical_depth
    real(8), intent(in) :: aerosol_scattering_optical_depth
    real(8), intent(in) :: cloud_optical_depth
    real(8), intent(in) :: cloud_scattering_optical_depth
    real(8), intent(in) :: total_scattering_optical_depth
    real(8), intent(in) :: total_optical_depth
    real(8), intent(in) :: combined_phase_coef_0
    real(8), intent(in) :: combined_phase_coef_1
    real(8), intent(in) :: combined_phase_coef_2
    real(8), intent(in) :: combined_phase_coef_3
    real(8), intent(in) :: combined_phase_coef_10
    real(8), intent(in) :: combined_phase_coef_20
    real(8), intent(in) :: combined_phase_coef_39

    integer :: trace_match_index
    real(8) :: nan_value

    call o2a_trace_init()
    if (.not. trace_enabled) return
    active_wavelength_nm = wavelength_nm
    trace_match_index = find_trace_wavelength_index(wavelength_nm)
    if (trace_match_index <= 0) return

    nan_value = ieee_value(0.0d0, ieee_quiet_nan)
    write(sublayer_optics_raw_unit, '(*(g0,:,","))') wavelength_nm, trace_wavelengths_nm(trace_match_index), global_sublayer_index, interval_index_1based, &
      pressure_hpa, temperature_k, number_density_cm3, oxygen_number_density_cm3, line_cross_section_cm2_per_molecule, &
      nan_value, cia_sigma_cm5_per_molecule2, gas_absorption_optical_depth, gas_scattering_optical_depth, cia_optical_depth, path_length_cm, &
      aerosol_optical_depth, aerosol_scattering_optical_depth, cloud_optical_depth, cloud_scattering_optical_depth, &
      total_scattering_optical_depth, total_optical_depth, combined_phase_coef_0, combined_phase_coef_1, combined_phase_coef_2, &
      combined_phase_coef_3, combined_phase_coef_10, combined_phase_coef_20, combined_phase_coef_39
    flush(sublayer_optics_raw_unit)
  end subroutine o2a_trace_sublayer_optics

  subroutine o2a_trace_fourier_term(i_fourier, refl_fc, surface_refl_fc, surface_e_view, surface_u_view_solar, fourier_weight)
    integer, intent(in) :: i_fourier
    real(8), intent(in) :: refl_fc
    real(8), intent(in) :: surface_refl_fc
    real(8), intent(in) :: surface_e_view
    real(8), intent(in) :: surface_u_view_solar
    real(8), intent(in) :: fourier_weight

    integer :: trace_match_index

    call o2a_trace_init()
    if (.not. trace_enabled) return
    if (active_wavelength_nm <= 0.0d0) return
    trace_match_index = find_trace_wavelength_support_index(active_wavelength_nm)
    if (trace_match_index <= 0) return

    write(fourier_terms_unit, '(*(g0,:,","))') trace_wavelengths_nm(trace_match_index), active_wavelength_nm, &
      i_fourier, refl_fc, refl_fc - surface_refl_fc, surface_refl_fc, surface_e_view, surface_u_view_solar, fourier_weight, fourier_weight * refl_fc
    flush(fourier_terms_unit)
  end subroutine o2a_trace_fourier_term

  subroutine o2a_trace_transport_layer(layer_index, optical_depth, scattering_optical_depth, single_scatter_albedo, &
      phase_coef_0, phase_coef_1, phase_coef_2, phase_coef_3, phase_coef_10, phase_coef_20, phase_coef_39)
    integer, intent(in) :: layer_index
    real(8), intent(in) :: optical_depth
    real(8), intent(in) :: scattering_optical_depth
    real(8), intent(in) :: single_scatter_albedo
    real(8), intent(in) :: phase_coef_0
    real(8), intent(in) :: phase_coef_1
    real(8), intent(in) :: phase_coef_2
    real(8), intent(in) :: phase_coef_3
    real(8), intent(in) :: phase_coef_10
    real(8), intent(in) :: phase_coef_20
    real(8), intent(in) :: phase_coef_39

    integer :: trace_match_index

    call o2a_trace_init()
    if (.not. trace_enabled) return
    if (active_wavelength_nm <= 0.0d0) return
    trace_match_index = find_trace_wavelength_support_index(active_wavelength_nm)
    if (trace_match_index <= 0) return

    write(transport_layers_unit, '(*(g0,:,","))') trace_wavelengths_nm(trace_match_index), active_wavelength_nm, &
      layer_index, optical_depth, scattering_optical_depth, single_scatter_albedo, &
      phase_coef_0, phase_coef_1, phase_coef_2, phase_coef_3, phase_coef_10, phase_coef_20, phase_coef_39
    flush(transport_layers_unit)
  end subroutine o2a_trace_transport_layer

  integer function find_trace_wavelength_index(wavelength_nm)
    real(8), intent(in) :: wavelength_nm
    integer :: index

    find_trace_wavelength_index = 0
    do index = 1, trace_wavelength_count
      if (abs(wavelength_nm - trace_wavelengths_nm(index)) <= wavelength_match_tolerance_nm) then
        find_trace_wavelength_index = index
        return
      end if
    end do
  end function find_trace_wavelength_index

  integer function find_trace_wavelength_support_index(wavelength_nm)
    real(8), intent(in) :: wavelength_nm
    integer :: index
    real(8) :: best_delta
    real(8) :: delta

    find_trace_wavelength_support_index = 0
    best_delta = wavelength_support_tolerance_nm
    do index = 1, trace_wavelength_count
      delta = abs(wavelength_nm - trace_wavelengths_nm(index))
      if (delta <= best_delta) then
        best_delta = delta
        find_trace_wavelength_support_index = index
      end if
    end do
  end function find_trace_wavelength_support_index

  integer function o2a_trace_wavelength_count_value()
    call o2a_trace_init()
    o2a_trace_wavelength_count_value = trace_wavelength_count
  end function o2a_trace_wavelength_count_value

  real(8) function o2a_trace_wavelength_nm_value(index)
    integer, intent(in) :: index

    call o2a_trace_init()
    if (index < 1 .or. index > trace_wavelength_count) then
      o2a_trace_wavelength_nm_value = ieee_value(0.0d0, ieee_quiet_nan)
      return
    end if
    o2a_trace_wavelength_nm_value = trace_wavelengths_nm(index)
  end function o2a_trace_wavelength_nm_value

  subroutine parse_wavelength_list(buffer)
    character(len=*), intent(in) :: buffer
    integer :: start_index
    integer :: comma_index
    character(len=64) :: token

    trace_wavelength_count = 0
    start_index = 1
    do
      if (start_index > len_trim(buffer)) exit
      comma_index = index(buffer(start_index:), ',')
      if (comma_index == 0) then
        token = adjustl(buffer(start_index:len_trim(buffer)))
        call append_trace_wavelength(trim(token))
        exit
      end if
      token = adjustl(buffer(start_index:start_index + comma_index - 2))
      call append_trace_wavelength(trim(token))
      start_index = start_index + comma_index
    end do
  end subroutine parse_wavelength_list

  subroutine append_trace_wavelength(token)
    character(len=*), intent(in) :: token
    real(8) :: parsed
    integer :: ios

    if (len_trim(token) == 0) return
    if (trace_wavelength_count >= max_trace_wavelengths) return
    read(token, *, iostat=ios) parsed
    if (ios /= 0) return
    trace_wavelength_count = trace_wavelength_count + 1
    trace_wavelengths_nm(trace_wavelength_count) = parsed
  end subroutine append_trace_wavelength

  subroutine open_trace_file(unit_number, file_name, header_line)
    integer, intent(inout) :: unit_number
    character(len=*), intent(in) :: file_name
    character(len=*), intent(in) :: header_line
    character(len=path_length) :: full_path

    if (unit_number > 0) return

    full_path = trim(trace_root) // '/' // trim(file_name)
    open(newunit=unit_number, file=trim(full_path), status='replace', action='write', form='formatted')
    write(unit_number, '(A)') trim(header_line)
    flush(unit_number)
  end subroutine open_trace_file

end module o2aFunctionTraceModule
