# Python Plotting Library

This document records the recommended `zdisamar.plot` design. It is a versioned
implementation target for the Python plotting package, not a statement that the
plotting package already exists.

The Python plotting package should be separate from the core wrapper. It should
accept `Spectrum`, `DiagnosticTable`, current NumPy structured arrays, Pandas
data frames, or already-materialized CSVs. The forward model remains:

```text
input -> forward model -> output
```

Plotting consumes outputs and diagnostics only.

Every generated plot artifact should include the full sampled spectrum for
orientation. A plot may add a focused diagnostic panel or a wavelength-window
panel, but the saved artifact must still include the full sampled spectrum
unless the artifact itself is already the full sampled spectrum.

## Executive Recommendation

Implement the first release around eight plot families, in this order.

First, implement spectrum and validation plots: reflectance, radiance,
irradiance, current-versus-reference overlays, signed residuals, residual
histograms, and one-to-one comparisons. These are the most common sanity checks
in O2 A-band retrieval and validation work, and they match the repository's
current parity workflow. OCO-2/ACOS validation uses filtering, reference
comparisons, one-to-one lines, fit lines, and reported residual statistics;
TROPOMI ALH validation uses histograms, one-to-one comparisons, map or curtain
context, and land/ocean separation. [S3]

Second, implement atmosphere budget plots: altitude or pressure profiles,
optical-depth component stacks, and wavelength-altitude heatmaps. DISAMAR is
layer-based and explicitly uses atmosphere intervals, Gaussian layer
subdivisions, doubling-adding, layer-based orders of scattering, and
pseudo-spherical correction; the repo already exposes layer and sublayer
optical-depth rows. [S1]

Third, implement O2 line diagnostics: line-center markers, line contribution
stems, weak/strong/line-mixing partition bars, isotope contribution bars, and
line-status counts. O2 A-band spectroscopy accuracy depends on line shape, line
mixing, and collision-induced absorption; current laboratory and database work emphasizes accurate line
intensities, cross sections, and line-by-line parameterization. [S4]

Fourth, implement collision-induced absorption plots: collision-induced absorption optical-depth profiles, collision-induced absorption share of total
absorption, collision-induced absorption share of total optical depth, and collision-induced absorption cross-section diagnostics
against temperature and pressure. HITRAN has a dedicated collision-induced absorption section, O2-O2
files are included in HITRAN2024, and current collision-induced absorption updates extend O2-O2 and
related data. [S6]

Fifth, implement aerosol and cloud plots: aerosol share spectra, aerosol layer
profiles, cloud optical-depth profiles, and cloud/aerosol sensitivity plots. O2
A-band ALH work depends on the absorption structure of the band, surface albedo,
aerosol layer height, aerosol optical thickness, and validation against
CALIOP/ATLID; cloud algorithms such as FRESCO+ and SACURA use O2 A-band
absorption to infer cloud pressure or cloud top height. [S2]

Sixth, implement instrument response plots: response kernels, support-width
summaries, weight matrices, and nominal/support wavelength overlays. Instrument
spectral response functions directly affect retrieval accuracy; current work
still plots ISRF shapes, residuals, ISRF errors, and response-function
variation. [S14]

Seventh, implement radiative-transfer diagnostic plots: cumulative optical depth
above, transmission proxies, source/loss proxy profiles, and proxy share bars.
This fits DISAMAR's layer-based radiative-transfer design and the repo's current
proxy diagnostic table. [S1]

Eighth, implement perturbation and sensitivity plots: delta reflectance versus
wavelength, sensitivity heatmaps, and max-delta summary bars. O2 A-band
retrieval papers use derivatives, optimal estimation, information content, and
error propagation; the current wrapper already exposes coarse parameter
perturbation outputs. [S11]

## Source Key

| Key | Citation metadata | DOI or URL | Plot types or diagnostic forms seen | Why it matters for `zdisamar` |
| --- | --- | --- | --- | --- |
| S1 | de Haan, Wang, Sneep, Veefkind, Stammes, 2022, "Introduction of the DISAMAR radiative transfer model," Geoscientific Model Development | DOI: 10.5194/gmd-15-7031-2022 | Altitude-grid schematics; DISAMAR-vs-DAK reflectance comparison; derivative comparison; altitude-resolved air-mass-factor profile | Anchors layer plots, RT diagnostics, derivative checks, and validation/parity overlays. |
| S2 | de Graaf, Sneep, ter Linden, Tilstra, Donovan, van Zadelhoff, Veefkind, 2025, "Improvements in aerosol layer height retrievals from TROPOMI oxygen A-band measurements by surface albedo fitting in optimal estimation," Atmospheric Measurement Techniques | DOI: 10.5194/amt-18-2553-2025 | ALH histograms, CALIOP/TROPOMI one-to-one plots, curtain plots, land/ocean color split, QA/AOT/albedo filtering | Motivates validation plots, aerosol/surface-albedo sensitivity plots, and O2 A-band spectral-window defaults. |
| S3 | O'Dell et al., 2018, "Improved retrievals of carbon dioxide from Orbiting Carbon Observatory-2 with the version 8 ACOS algorithm," Atmospheric Measurement Techniques | DOI: 10.5194/amt-11-6539-2018 | Filtering maps, bias-correction plots, TCCON one-to-one validation panels, fit lines, residual statistics | Motivates parity metrics, one-to-one validation, reference overlays, and O2 A-band screening residuals. |
| S4 | Drouin et al., 2016/2017, "Multispectrum analysis of the oxygen A-band," Journal of Quantitative Spectroscopy and Radiative Transfer | DOI: 10.1016/j.jqsrt.2016.03.037 | Multispectrum spectroscopy diagnostics; line-shape, line-mixing, collision-induced absorption and ABSCO database outputs | Motivates line-shape, line-mixing, O2 line contribution, and collision-induced absorption budget plots. |
| S5 | Adkins, Yurchenko, Somogyi, Hodges, 2025, "An Accurate Determination of O2 A-band Line Intensities through Experiment and Theory," Journal of Quantitative Spectroscopy and Radiative Transfer | DOI: 10.1016/j.jqsrt.2025.109412 | Measured-versus-theory intensity comparisons and line-intensity uncertainty diagnostics | Supports line-strength and isotope/branch diagnostics for O2 A-band spectroscopy. |
| S6 | HITRANonline collision-induced absorption section and Terragni et al. HITRAN2024 collision-induced absorption update, 2025 | HITRAN collision-induced absorption page; JQSRT 347, article 109631 | collision-induced absorption tables by collisional pair, spectral range, and temperature; database update summaries | Motivates O2-O2 collision-induced absorption optical-depth, cross-section, and contribution-share plots. |
| S7 | Wang, Stammes, van der A, Pinardi, van Roozendael, 2008, "FRESCO+: an improved O2 A-band cloud retrieval algorithm," Atmospheric Chemistry and Physics | DOI: 10.5194/acp-8-6565-2008 | Cloud fraction/cloud pressure comparisons; simulated and measured O2 A-band use | Supports cloud pressure, cloud optical depth, and cloud correction diagnostics. |
| S8 | Kokhanovsky et al., 2006, "The semianalytical cloud retrieval algorithm for SCIAMACHY II," Atmospheric Chemistry and Physics | DOI: 10.5194/acp-6-4129-2006 | SCIAMACHY/MERIS cloud retrieval comparisons; O2 A-band 755-775 nm cloud top height use | Supports cloud optical-depth/profile plots and O2 A-band cloud-window defaults. |
| S9 | van Diedenhoven, Hasekamp, Aben, 2005, "Surface pressure retrieval from SCIAMACHY measurements in the O2 A Band," Atmospheric Chemistry and Physics | DOI: 10.5194/acp-5-2109-2005 | Surface-pressure validation, aerosol sensitivity, calibration-offset discussion | Motivates validation residuals, continuum-offset diagnostics, surface-pressure and albedo-sensitivity plots. |
| S10 | Richardson and Stephens, 2018, "Information content of OCO-2 oxygen A-band channels for retrieving marine liquid cloud properties," Atmospheric Measurement Techniques | DOI: 10.5194/amt-11-1515-2018 | Micro-window spectra, covariance heatmaps, information-content curves, posterior-error panels, retrieval iteration traces | Motivates micro-window markers, instrument-response plots, information-content plots, and future retrieval-iteration panels. |
| S11 | Sanders and de Haan, 2013, "Retrieval of aerosol parameters from the oxygen A band in the presence of chlorophyll fluorescence," Atmospheric Measurement Techniques | DOI: 10.5194/amt-6-2725-2013 | Precision and error-propagation diagnostics using forward-model derivatives | Motivates perturbation, derivative, and sensitivity spectra. |
| S12 | Nanda et al., 2018, "Error sources in the retrieval of aerosol information over bright surfaces from satellite measurements in the oxygen A band," Atmospheric Measurement Techniques | DOI: 10.5194/amt-11-161-2018 | Synthetic O2 A-band spectra, path/surface contribution decomposition, derivative plots, sensitivity/error plots | Motivates aerosol share, path-versus-surface decomposition, and surface-albedo sensitivity plots. |
| S13 | Nanda et al., 2018, "A weighted least squares approach to retrieve aerosol layer height over bright surfaces applied to GOME-2 measurements of the oxygen A band," Atmospheric Measurement Techniques | DOI: 10.5194/amt-11-3263-2018 | Weighted spectral residual/error treatment, dynamic weighting by wavelength, GOME-2 case comparisons | Motivates wavelength-dependent uncertainty or weighting overlays. |
| S14 | El Haouari et al., 2025, "In-flight estimation of instrument spectral response functions using sparse representations," Atmospheric Measurement Techniques | DOI: 10.5194/amt-18-2573-2025 | ISRF shape overlays, dictionary atoms, residuals, ISRF estimation error panels | Motivates response-kernel, response-matrix, residual, and support-width plots. |
| S15 | van Hees et al., 2018, "Determination of the TROPOMI-SWIR instrument spectral response function," Atmospheric Measurement Techniques | DOI: 10.5194/amt-11-3917-2018 | ISRF calibration curves and monitoring diagnostics | Supports instrument-response plotting, even though the paper is SWIR rather than O2 A NIR. |

## Literature-Derived Plot Catalog

| Plot ID | Family | Priority | Source basis | Scientific question | Data input | X axis | Y axis | Encoding | Color or facet | Subplots | Overlays | Default window | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `reflectance_spectrum` | spectrum | P0 | S1, S2, S3, S12 | What is the modeled O2 A-band reflectance structure? | `Spectrum` or data frame with `wavelength_nm`, `reflectance` | `wavelength_nm`, nm, linear | `reflectance`, unitless, linear | line | single black or quantity color | 1 | optional minimum-reflectance point, selected wavelength rules | input grid, normally 755-776 nm | Default first plot. Keep line thin; no smoothing. |
| `radiance_spectrum` | spectrum | P0 | S1, S3, S13 | What radiance is emitted to the instrument grid? | `Spectrum` | `wavelength_nm`, nm | `radiance`, native model units | line | quantity color | 1 | optional reference radiance | full grid | Do not rename units unless native units are exposed. |
| `irradiance_spectrum` | spectrum | P0 | S1, S3, S13 | Is the solar/input irradiance path consistent? | `Spectrum` | `wavelength_nm`, nm | `irradiance`, native model units | line | quantity color | 1 | optional reference irradiance | full grid | Useful for parity failures where reflectance hides common scaling issues. |
| `spectrum_triplet` | spectrum | P0 | S1, S3 | Do reflectance, radiance, and irradiance look consistent together? | `Spectrum` | shared `wavelength_nm`, nm | reflectance/radiance/irradiance | three vertically stacked line charts | facet by quantity; semantic colors | 3 rows x 1 column | selected wavelength rules | full grid | Return `alt.VConcatChart`; independent y scales, shared x. |
| `model_reference_overlay` | validation | P0 | S1, S3, S9 | Does current `zdisamar` match a reference spectrum? | current `Spectrum`; reference data frame or CSV | `wavelength_nm`, nm | selected quantity | layered lines | source: current/reference; restrained two-line palette | 1 per quantity | optional min marker | full grid or validation grid | Reference is interpolated to current grid by plotting helper. |
| `spectral_residual` | validation | P0 | S1, S3, S9 | Where does current minus reference differ spectrally? | current plus reference | `wavelength_nm`, nm | `residual`, same units as quantity | line plus zero rule | residual sign via positive/negative semantic colors, or one black line | 1 | zero line; optional tolerance band | full grid | Also support `relative=True` for `(current-reference)/reference`. |
| `residual_histogram` | validation | P0 | S2, S3 | What is the residual distribution? | residual data frame | `residual`, quantity units | count or density | histogram | facet by quantity or land/ocean for validation products | 1 or facets | mean and median rules | all rows | Use compact bin counts; no dashboard styling. |
| `validation_metrics_bar` | validation | P0 | S3 | Which quantity has the largest parity error? | metrics table from current/reference | metric: `mae`, `rmse`, `max_abs`, `mean_signed` | value | grouped bar | color by metric; facet by quantity | 1 | optional threshold rule | all quantities | Mirrors repo's JSON parity metrics. |
| `one_to_one_scatter` | validation | P1 | S2, S3 | Does modeled or retrieved output agree with reference values? | paired table with `current`, `reference`, optional group | `reference` | `current` | points plus rule/fit line | group: source, surface type, scene class | 1 or small multiples | one-to-one line; best-fit line; summary text | all paired values | For retrieval validation, not only spectrum parity. |
| `o2_line_window` | o2_lines | P0 | S4, S5, S10, S12 | Which O2 lines sit inside a selected spectral window? | `Spectrum` plus `O2LineContributions` | `wavelength_nm`, nm | reflectance on top; line contribution on bottom | top line; bottom lollipop/stem | line kind: weak/strong/line mixing | 2 rows x 1 column | vertical line-center rules; selected wavelength marker | around selected wavelength, default +/-0.5 nm | Main spectroscopy plot. |
| `o2_line_contribution_stems` | o2_lines | P0 | S4, S5 | Which line centers dominate cross section near sampled wavelengths? | `O2LineContributions` | `center_wavelength_nm`, nm | `abs_total_sigma_cm2_per_molecule`, log allowed | stem or point+rule | `row_kind_label`, `status_label`; weak/strong palette | facet by `wavelength_nm` if multiple | selected wavelength rule | selected diagnostic wavelengths | Sort top `n` by absolute total sigma. |
| `o2_line_partition_bar` | o2_lines | P0 | S4, S5 | How much comes from weak lines, strong-line sidecars, and line mixing? | `O2LineContributions` aggregated by selected wavelength | component name | sum of absolute sigma | stacked or grouped bar | component: weak, strong, line_mixing | 1 or facet by wavelength | none | selected diagnostic wavelengths | Components: `weak_line_sigma_cm2_per_molecule`, `strong_line_sigma_cm2_per_molecule`, `line_mixing_sigma_cm2_per_molecule`. |
| `o2_line_status_counts` | o2_lines | P1 | S4, S5 | Are lines included, excluded, sidecarred, or cut off as expected? | `O2LineContributions` | `status_label` | row count | bar | color by `row_kind_label` | 1 | optional text count | selected rows | Good for debugging threshold and strong-line logic. |
| `o2_isotope_contribution_bar` | o2_lines | P1 | S4, S5 | Which isotope contributes most? | `O2LineContributions` | `isotope_number` or `isotopologue_code` | sum `abs_total_sigma_cm2_per_molecule` | bar | isotope palette: grayscale or restrained categorical | 1 | optional labels | selected wavelengths | Use log y when large dynamic range. |
| `o2_cross_section_profile` | o2_lines | P1 | S4, S5 | How do dominant line contributions vary with altitude/pressure? | `O2LineContributions` | `total_sigma_cm2_per_molecule` or abs value | `altitude_km` or `pressure_hpa` | line or points | top line centers; color by `center_wavelength_nm` | 1 or facet by sampled wavelength | zero line if signed | top N lines | Use pressure reversed/log if `y="pressure_hpa"`. |
| `optical_depth_profile` | atmosphere | P0 | S1, S2, S12 | Which layers contribute optical depth at selected wavelengths? | `AtmosphericBudget` | selected quantity, such as `total_optical_depth` | `altitude_km` or `pressure_hpa` | line/point | color by `wavelength_nm`; facet by component optional | 1 | optional layer boundary rules | selected wavelengths | Default y is altitude increasing upward; pressure y is reversed. |
| `optical_depth_heatmap` | atmosphere | P0 | S1, S2, S12 | Where in wavelength-altitude space is optical depth concentrated? | `AtmosphericBudget` covering many wavelengths | `wavelength_nm`, nm | `altitude_km` or `pressure_hpa` | heatmap | color by selected optical-depth quantity | 1 | selected wavelength rules | full or sampled grid | Use continuous single-hue palette; allow log transform for color. |
| `optical_depth_component_stack` | atmosphere | P0 | S1, S7, S12 | How does total optical depth split among gas, scattering, collision-induced absorption, aerosol, cloud? | `AtmosphericBudget` aggregated by wavelength | `wavelength_nm`, nm | column-summed optical depth | stacked area | component palette: absorption, scattering, collision-induced absorption, aerosol, cloud | 1 | optional total line | full grid | Components from current table: gas absorption, gas scattering, collision-induced absorption, aerosol, cloud. |
| `single_scatter_albedo_profile` | atmosphere | P1 | S2, S12 | How does single-scatter albedo vary vertically? | `AtmosphericBudget` | `single_scatter_albedo` | `altitude_km` or `pressure_hpa` | line | color by `wavelength_nm` | 1 | valid range 0-1 rule | selected wavelengths | Important for aerosol/cloud sensitivity and scattering diagnostics. |
| `aerosol_share_spectrum` | aerosol | P0 | S2, S11, S12, S13 | Which wavelengths are most affected by aerosol optical depth or scattering? | `AtmosphericBudget` aggregated by wavelength | `wavelength_nm`, nm | share: `sum(aerosol_optical_depth)/sum(total_optical_depth)` or scattering share | line | one line per share type | 1 | optional max marker | full or sampled grid | This directly matches the current harness science questions. |
| `aerosol_optical_depth_profile` | aerosol | P1 | S2, S12 | Where is aerosol optical depth placed vertically? | `AtmosphericBudget` | `aerosol_optical_depth` | `altitude_km` or `pressure_hpa` | line/area | color by wavelength | 1 | aerosol layer center marker if input available | selected wavelengths | Use area fill only when nonnegative. |
| `cloud_optical_depth_profile` | cloud | P1 | S7, S8, S10 | Where is cloud optical depth placed vertically? | `AtmosphericBudget` | `cloud_optical_depth` | `altitude_km` or `pressure_hpa` | line/area | color by wavelength | 1 | cloud top/base rules if available | selected wavelengths | Current default may be zero; still design it because cloud fields exist. |
| `cloud_share_spectrum` | cloud | P1 | S7, S8, S10 | Which spectral points are cloud-dominated? | `AtmosphericBudget` aggregated by wavelength | `wavelength_nm`, nm | `sum(cloud_optical_depth)/sum(total_optical_depth)` | line | cloud semantic color | 1 | FRESCO/SACURA window markers | 755-775 nm | Useful for future cloud-enabled cases. |
| `cia_share_profile` | cia | P0 | S4, S6 | Where is O2-O2 collision-induced absorption important relative to total absorption? | `OxygenCollisionInducedAbsorptionDiagnostics` | `cia_share_of_total_absorption` | `altitude_km` or `pressure_hpa` | line | color by `wavelength_nm` | 1 | zero/reference rules | selected wavelengths | y pressure reversed when chosen. |
| `cia_share_spectrum` | cia | P0 | S4, S6 | Which wavelengths are dominated by collision-induced absorption share? | `OxygenCollisionInducedAbsorptionDiagnostics` aggregated by wavelength | `wavelength_nm`, nm | `sum(cia_optical_depth)/sum(total_absorption_optical_depth)` | line | collision-induced absorption semantic color | 1 | max marker | full or sampled grid | Use total optical-depth share as optional second line. |
| `cia_cross_section_temperature` | cia | P1 | S4, S6 | Does derived collision-induced absorption cross section vary consistently with temperature and pressure? | `OxygenCollisionInducedAbsorptionDiagnostics` | `temperature_k` | `cia_cross_section_cm5_per_molecule2` | point or line | color by `pressure_hpa`; facet by wavelength | facets by wavelength | none | selected wavelengths | Use log y by default when values span orders. |
| `instrument_response_kernel` | instrument_response | P0 | S10, S14, S15 | What high-resolution wavelengths feed a nominal grid point? | `InstrumentResponseDiagnostics.sampling_table()` | `offset_nm` or `support_wavelength_nm` | `weight` | line or area | color by channel; facet by nominal wavelength | 1 or small multiples | center-wavelength rule; FWHM markers | selected nominal wavelengths | Use line for signed/shape emphasis, area only for normalized nonnegative weights. |
| `instrument_response_matrix` | instrument_response | P1 | S10, S14 | How do response weights map support wavelength to nominal wavelength? | sampling table with many nominal wavelengths | `support_wavelength_nm` | `nominal_wavelength_nm` | heatmap | color by `weight` | 1 | diagonal rule | sampled nominal grid | Plot is compact and useful for resampling bugs. |
| `instrument_support_width` | instrument_response | P0 | S10, S14, S15 | Which nominal wavelengths have broadest support? | sampling table aggregated by nominal/channel | `nominal_wavelength_nm` | `support_width_nm` or `support_count` | line/point | color by channel | 1 | selected wavelength markers | sampled nominal grid | Directly matches current harness questions. |
| `instrument_weight_rank` | instrument_response | P1 | S14 | Which support samples dominate a nominal wavelength? | sampling table for one nominal wavelength | `sample_index` or `offset_nm` | `weight` | bar or lollipop | channel facet | 1 or 2 facets | center rule | one nominal wavelength | Good for debugging kernel normalization. |
| `rt_source_profile` | radiative_transfer | P0 | S1, S12 | Which layers dominate scattering source and absorption loss proxies? | `RadiativeTransferDiagnostics` | proxy value | `altitude_km` or `pressure_hpa` | line | proxy component; facet by wavelength | facets by wavelength | optional layer labels | selected wavelengths | Components: `atmospheric_scattering_source_proxy`, `absorption_loss_proxy`. |
| `rt_cumulative_transmission` | radiative_transfer | P0 | S1 | How much atmosphere lies above each layer and how much direct transmission remains? | `RadiativeTransferDiagnostics` | `cumulative_optical_depth_above` or `direct_surface_transmission_proxy` | `altitude_km` | line | color by quantity and wavelength | 1 or facets | surface/top markers | selected wavelengths | Use independent x scales when plotting optical depth and transmission together. |
| `rt_proxy_share_bar` | radiative_transfer | P1 | S1, S12 | Which pathway dominates the selected RT proxy budget? | `RadiativeTransferDiagnostics` aggregated by wavelength | component | normalized contribution | stacked/grouped bar | component palette | facet by wavelength | optional labels | selected wavelengths | Useful for compact summaries. |
| `pseudo_spherical_airmass_profile` | radiative_transfer | P2 | S1 | What pseudo-spherical airmass factor is used with the selected geometry? | `RadiativeTransferDiagnostics` | `pseudo_spherical_airmass_factor` | `altitude_km` | rule or point/line | color by wavelength | 1 | geometric airmass text | selected wavelengths | Current value is constant per case; plot is mostly annotation. |
| `perturbation_delta_reflectance` | perturbation | P0 | S11, S12, S13 | Where does a parameter change alter reflectance? | `PerturbationResult` or concatenated results | `wavelength_nm`, nm | `delta_reflectance` | line | color by perturbation label | 1 | zero line; max-abs marker | full grid | Primary sensitivity plot. |
| `perturbation_abs_delta_reflectance` | perturbation | P0 | S11, S12 | Which wavelengths are most sensitive regardless of sign? | `PerturbationResult` | `wavelength_nm`, nm | `abs_delta_reflectance` | line | color by label | 1 | max marker | full grid | Useful for ranking top wavelengths. |
| `perturbation_delta_heatmap` | perturbation | P1 | S11, S12, S13 | Which perturbations affect which wavelengths? | list of `PerturbationResult` | `wavelength_nm` | perturbation label | heatmap | color by signed `delta_reflectance` with diverging palette | 1 | zero-centered color scale | full grid | Only plot when all results are on same wavelength grid or interpolated. |
| `perturbation_summary_bar` | perturbation | P0 | S11, S12 | Which parameter has the largest spectral effect? | list of `PerturbationResult.summary` | perturbation label | `max_abs_delta_reflectance` or mean absolute delta | bar | optional color by parameter family | 1 | labels with max wavelength | all perturbations | Good report-bundle panel. |
| `micro_window_marker_spectrum` | bundle | P1 | S10, S2, S7, S8 | Which retrieval windows are being emphasized? | `Spectrum`, optional named windows | `wavelength_nm` | reflectance | line plus shaded intervals | window name | 1 | shaded windows, selected wavelengths | 755-776 nm | Defaults: full O2 A; OCO-2 cloud micro-window 763.5-764.6 nm if requested. |
| `information_content_micro_window` | validation | P2 | S10 | Which spectral channels contain the most retrieval information? | proposed future table with `window_center_nm`, `window_size`, `information_content_bits`, `degrees_of_freedom`, posterior sigmas | `window_center_nm` | IC, degrees of freedom, or posterior sigma | line | color by window size; facet by metric | multiple metric facets | selected window rule | instrument-specific | Requires Jacobian/covariance outputs not currently exposed. |
| `retrieval_iteration_trace` | validation | P2 | S10, S2 | Does an inversion converge? | proposed future retrieval-iteration table | iteration index | state value or cost | line | color by state variable or chi-squared | facets by variable | truth/prior rules | retrieval runs only | Keep outside P0 because `zdisamar` currently exposes forward-model diagnostics, not retrieval iterations. |
| `spectral_covariance_heatmap` | validation | P2 | S10, S13 | Are spectral errors correlated across channels? | proposed future covariance matrix | wavelength/channel i | wavelength/channel j | heatmap | color by covariance/correlation | 1 | selected-window boxes | instrument-specific | Useful for weighted least squares and information-content studies. |

## Recommended Plot Bundles

### `o2a_forward_summary`

Panels, in order: `reflectance_spectrum`, `radiance_spectrum`,
`irradiance_spectrum`, `micro_window_marker_spectrum` or selected-wavelength
marker strip. Layout: four rows, one column, shared x axis, independent y axes.
Markers: minimum reflectance point on reflectance; vertical rules for selected
wavelengths such as 755.0, 760.76, and 776.0 nm. API accepts `Spectrum`;
optional `case` for geometry/instrument annotations. Return type:
`alt.VConcatChart`.

### `validation_against_reference`

Panels, in order: reflectance overlay, radiance overlay, irradiance overlay,
reflectance residual, radiance residual, irradiance residual, residual
histogram, metrics bar. Layout: first six panels as three two-row groups, then
histogram and metrics below; shared x only within spectral panels. Markers: zero
residual line, optional tolerance band, maximum absolute residual point. API
accepts current `Spectrum`, reference spectrum table/CSV, interpolation mode,
quantity list. Return type: `alt.VConcatChart`.

### `o2_line_window`

Panels, in order: reflectance spectrum in selected window, line contribution
stems, weak/strong/line-mixing partition bar, status count bar. Layout: two
wide spectral panels stacked, then two compact bars below. Shared x for the
first two panels. Markers: selected model wavelength rule, line-center stems,
optional strong-line labels. API accepts `Spectrum`, `O2LineContributions`,
`window_nm`, `top_n`, `quantity="abs_total_sigma_cm2_per_molecule"`. Return
type: `alt.VConcatChart`.

### `atmospheric_budget`

Panels, in order: optical-depth heatmap, optical-depth component stack,
selected-wavelength optical-depth profiles, single-scatter-albedo profile.
Layout: heatmap full width; stack full width; profiles in two columns. Shared
wavelength axis for heatmap and stack; independent y axes for profiles. Markers:
selected wavelength rules, layer boundary rules if present. API accepts
`AtmosphericBudget`; optional `wavelengths_nm`, `components`, `vertical_axis`.
Return type: `alt.VConcatChart`.

### `collision_induced_absorption_budget`

Panels, in order: collision-induced absorption share spectrum, collision-induced absorption share profile, collision-induced absorption optical-depth
profile, collision-induced absorption cross-section versus temperature/pressure. Layout: two rows x two
columns. Shared selected wavelength coloring. Markers: maximum collision-induced absorption share point,
optional pressure labels. API accepts `OxygenCollisionInducedAbsorptionDiagnostics` table. Return type:
`alt.VConcatChart` or nested `alt.HConcatChart`.

### `instrument_response`

Panels, in order: response kernel for selected nominal wavelength, support-width
line over nominal wavelength, response matrix heatmap, dominant support-sample
lollipop. Layout: kernel and width on top row; matrix full width; lollipop
bottom. Shared x only where meaningful. Markers: nominal center rule, FWHM
markers, selected wavelength rules. API accepts
`InstrumentResponseDiagnostics.sampling_table()` or bound
`prepared.instrument_response`. Return type: `alt.VConcatChart`.

### `radiative_transfer_budget`

Panels, in order: cumulative optical-depth/transmission profile, source/loss
proxy profile, proxy share bar, final reflectance/radiance annotation strip.
Layout: two profile panels side by side; bar and annotation below. Shared
vertical axis for profile panels. Markers: selected wavelengths, layer labels
for top-contributing layers. API accepts `RadiativeTransferDiagnostics` table
and optionally `Spectrum` for final reflectance/radiance. Return type:
`alt.VConcatChart`.

### `perturbation_sensitivity`

Panels, in order: signed delta reflectance, absolute delta reflectance,
perturbation delta heatmap, max-delta summary bar. Layout: two spectral panels
stacked, heatmap below, bar at bottom. Shared x axis across spectral and heatmap
panels. Markers: zero line, max-absolute-delta marker for each perturbation.
API accepts one `PerturbationResult` or a list of results. Return type:
`alt.VConcatChart`.

## Altair API Proposal

Package structure:

```text
python/zdisamar/plot/
  __init__.py
  fields.py
  theme.py
  io.py
  data.py
  spectrum.py
  validation.py
  atmosphere.py
  o2_lines.py
  collision_induced_absorption.py
  aerosol.py
  cloud.py
  instrument_response.py
  radiative_transfer.py
  perturbation.py
  bundles.py
  bound.py
```

The package should use Altair charts as the public return type. Static export
should call Altair's save path with `vl-convert-python` installed for SVG, PNG,
and PDF export. Do not make the core wrapper depend on Altair; `zdisamar.plot`
imports plotting dependencies separately.

Core helpers:

```python
zp.use_theme(name: Literal["journal", "monochrome", "labbook", "talk"] = "journal") -> None

zp.save(
    chart: alt.TopLevelMixin,
    path: str | Path,
    *,
    scale: float = 2.0,
    ppi: int = 300,
) -> None

zp.to_dataframe(obj: Spectrum | DiagnosticTable | np.ndarray | pd.DataFrame | Mapping) -> pd.DataFrame

zp.spectrum.with_full_sample_spectrum(
    chart: alt.TopLevelMixin,
    spectrum,
    *,
    quantity: str = zp.fields.REFLECTANCE,
    markers_nm: Sequence[float] = (),
) -> alt.VConcatChart
```

Recommended field constants:

```python
zp.fields.WAVELENGTH_NM = "wavelength_nm"
zp.fields.REFLECTANCE = "reflectance"
zp.fields.RADIANCE = "radiance"
zp.fields.IRRADIANCE = "irradiance"
zp.fields.TOTAL_OPTICAL_DEPTH = "total_optical_depth"
zp.fields.TOTAL_ABSORPTION_OPTICAL_DEPTH = "total_absorption_optical_depth"
zp.fields.TOTAL_SCATTERING_OPTICAL_DEPTH = "total_scattering_optical_depth"
zp.fields.COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH = "cia_optical_depth"
zp.fields.AEROSOL_OPTICAL_DEPTH = "aerosol_optical_depth"
zp.fields.CLOUD_OPTICAL_DEPTH = "cloud_optical_depth"
zp.fields.DELTA_REFLECTANCE = "delta_reflectance"
```

Direct spectrum functions:

```python
zp.spectrum.reflectance(
    spectrum,
    *,
    window_nm: tuple[float, float] | None = None,
    markers_nm: Sequence[float] = (),
    show_minimum: bool = True,
    title: str | None = None,
    width: int | None = None,
    height: int | None = None,
) -> alt.LayerChart | alt.Chart

zp.spectrum.radiance(spectrum, *, window_nm=None, markers_nm=(), title=None) -> alt.LayerChart | alt.Chart

zp.spectrum.irradiance(spectrum, *, window_nm=None, markers_nm=(), title=None) -> alt.LayerChart | alt.Chart

zp.spectrum.triplet(
    spectrum,
    *,
    window_nm: tuple[float, float] | None = None,
    markers_nm: Sequence[float] = (),
) -> alt.VConcatChart
```

Direct validation functions:

```python
zp.validation.overlay(
    current,
    reference,
    *,
    quantity: Literal["reflectance", "radiance", "irradiance"] = "reflectance",
    reference_label: str = "reference implementation",
    current_label: str = "zig implementation",
    window_nm: tuple[float, float] | None = None,
) -> alt.LayerChart

zp.validation.residual(
    current,
    reference,
    *,
    quantity: str = "reflectance",
    relative: bool = False,
    tolerance: float | None = None,
    window_nm: tuple[float, float] | None = None,
) -> alt.LayerChart

zp.validation.residual_histogram(
    current,
    reference,
    *,
    quantity: str = "reflectance",
    relative: bool = False,
    bins: int = 60,
) -> alt.LayerChart

zp.validation.residual_histogram_report(
    current,
    reference,
    *,
    quantity: str = "reflectance",
    residual_threshold: float,
    relative: bool = False,
    bins: int = 60,
) -> alt.VConcatChart

zp.validation.metrics_bar(
    current,
    reference,
    *,
    quantities: Sequence[str] = ("reflectance", "radiance", "irradiance"),
    metrics: Sequence[str] = ("mae", "rmse", "max_abs", "mean_signed"),
) -> alt.Chart

zp.validation.one_to_one(
    table,
    *,
    reference: str = "reference",
    current: str = "current",
    group: str | None = None,
    fit_line: bool = True,
) -> alt.LayerChart
```

Direct atmosphere and component functions:

```python
zp.atmosphere.optical_depth_heatmap(
    budget,
    *,
    quantity: str = zp.fields.TOTAL_OPTICAL_DEPTH,
    vertical_axis: Literal["altitude_km", "pressure_hpa"] = "altitude_km",
    log_color: bool = False,
    markers_nm: Sequence[float] = (),
) -> alt.LayerChart | alt.Chart

zp.atmosphere.optical_depth_profile(
    budget,
    *,
    quantity: str = zp.fields.TOTAL_OPTICAL_DEPTH,
    vertical_axis: Literal["altitude_km", "pressure_hpa"] = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
) -> alt.Chart

zp.atmosphere.component_stack(
    budget,
    *,
    components: Sequence[str] = (
        "gas_absorption_optical_depth",
        "gas_scattering_optical_depth",
        "cia_optical_depth",
        "aerosol_optical_depth",
        "cloud_optical_depth",
    ),
    aggregate_layers: bool = True,
) -> alt.Chart

zp.atmosphere.single_scatter_albedo_profile(
    budget,
    *,
    vertical_axis: str = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
) -> alt.Chart
```

Direct O2 line functions:

```python
zp.o2_lines.window(
    spectrum,
    lines,
    *,
    center_nm: float | None = None,
    window_nm: tuple[float, float] | None = None,
    top_n: int = 40,
    contribution: str = "abs_total_sigma_cm2_per_molecule",
) -> alt.VConcatChart

zp.o2_lines.contribution_stems(
    lines,
    *,
    contribution: str = "abs_total_sigma_cm2_per_molecule",
    top_n: int = 60,
    facet_by_wavelength: bool = True,
    log_y: bool = True,
) -> alt.LayerChart | alt.FacetChart

zp.o2_lines.partition_bar(
    lines,
    *,
    components: Sequence[str] = (
        "weak_line_sigma_cm2_per_molecule",
        "strong_line_sigma_cm2_per_molecule",
        "line_mixing_sigma_cm2_per_molecule",
    ),
    absolute: bool = True,
) -> alt.Chart

zp.o2_lines.status_counts(lines) -> alt.Chart

zp.o2_lines.isotope_bar(
    lines,
    *,
    value: str = "abs_total_sigma_cm2_per_molecule",
    aggregate: Literal["sum", "max"] = "sum",
) -> alt.Chart
```

Direct collision-induced absorption functions:

```python
zp.collision_induced_absorption.share_profile(
    collision_induced_absorption,
    *,
    share: Literal[
        "cia_share_of_total_absorption",
        "cia_share_of_total_optical_depth",
    ] = "cia_share_of_total_absorption",
    vertical_axis: str = "altitude_km",
) -> alt.Chart

zp.collision_induced_absorption.share_spectrum(
    collision_induced_absorption,
    *,
    denominator: Literal["absorption", "total"] = "absorption",
) -> alt.LayerChart

zp.collision_induced_absorption.cross_section_temperature(
    collision_induced_absorption,
    *,
    y: str = "cia_cross_section_cm5_per_molecule2",
    color: str = "pressure_hpa",
    log_y: bool = True,
) -> alt.Chart
```

Direct aerosol and cloud functions:

```python
zp.aerosol.share_spectrum(
    budget,
    *,
    share: Literal["total", "scattering", "absorption"] = "total",
) -> alt.LayerChart

zp.aerosol.optical_depth_profile(
    budget,
    *,
    vertical_axis: str = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
) -> alt.Chart

zp.cloud.share_spectrum(budget, *, share: Literal["total", "scattering", "absorption"] = "total") -> alt.LayerChart

zp.cloud.optical_depth_profile(
    budget,
    *,
    vertical_axis: str = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
) -> alt.Chart
```

Direct instrument-response functions:

```python
zp.instrument_response.kernel(
    response,
    *,
    nominal_wavelength_nm: float | None = None,
    channel: Literal["radiance", "irradiance"] | None = "radiance",
    x: Literal["offset_nm", "support_wavelength_nm"] = "offset_nm",
    as_area: bool = False,
) -> alt.LayerChart

zp.instrument_response.matrix(
    response,
    *,
    channel: Literal["radiance", "irradiance"] = "radiance",
) -> alt.Chart

zp.instrument_response.support_width(
    response,
    *,
    y: Literal["support_width_nm", "support_count"] = "support_width_nm",
) -> alt.Chart

zp.instrument_response.weight_rank(
    response,
    *,
    nominal_wavelength_nm: float,
    channel: Literal["radiance", "irradiance"] = "radiance",
    top_n: int | None = None,
) -> alt.LayerChart
```

Direct radiative-transfer functions:

```python
zp.radiative_transfer.source_profile(
    rt,
    *,
    components: Sequence[str] = (
        "atmospheric_scattering_source_proxy",
        "absorption_loss_proxy",
    ),
    vertical_axis: str = "altitude_km",
) -> alt.Chart

zp.radiative_transfer.cumulative_transmission(
    rt,
    *,
    vertical_axis: str = "altitude_km",
) -> alt.VConcatChart | alt.LayerChart

zp.radiative_transfer.proxy_share_bar(
    rt,
    *,
    components: Sequence[str] = (
        "atmospheric_scattering_source_proxy",
        "absorption_loss_proxy",
        "direct_surface_transmission_proxy",
    ),
    normalize: bool = True,
) -> alt.Chart
```

Direct perturbation functions:

```python
zp.perturbation.delta_reflectance(
    result_or_results,
    *,
    signed: bool = True,
    window_nm: tuple[float, float] | None = None,
    show_max: bool = True,
) -> alt.LayerChart

zp.perturbation.abs_delta_reflectance(
    result_or_results,
    *,
    window_nm: tuple[float, float] | None = None,
) -> alt.LayerChart

zp.perturbation.delta_heatmap(
    results,
    *,
    interpolate: bool = True,
    signed: bool = True,
) -> alt.Chart

zp.perturbation.summary_bar(
    results,
    *,
    metric: Literal["max_abs_delta_reflectance", "mean_abs_delta_reflectance"] = "max_abs_delta_reflectance",
) -> alt.LayerChart
```

Bundle functions:

```python
zp.bundles.o2a_forward_summary(
    spectrum,
    *,
    case=None,
    markers_nm: Sequence[float] = (755.0, 760.76, 776.0),
    window_nm: tuple[float, float] | None = None,
) -> alt.VConcatChart

zp.bundles.validation_against_reference(
    current,
    reference,
    *,
    quantities: Sequence[str] = ("reflectance", "radiance", "irradiance"),
    window_nm: tuple[float, float] | None = None,
) -> alt.VConcatChart

zp.bundles.o2_line_window(
    spectrum,
    lines,
    *,
    center_nm: float = 760.76,
    window_nm: tuple[float, float] | None = None,
    top_n: int = 40,
) -> alt.VConcatChart

zp.bundles.atmospheric_budget(budget, *, markers_nm=(755.0, 760.76, 776.0)) -> alt.VConcatChart

zp.bundles.collision_induced_absorption_budget(collision_induced_absorption) -> alt.VConcatChart

zp.bundles.instrument_response(response, *, nominal_wavelength_nm: float = 760.76) -> alt.VConcatChart

zp.bundles.radiative_transfer_budget(rt) -> alt.VConcatChart

zp.bundles.perturbation_sensitivity(results) -> alt.VConcatChart
```

Bound convenience helpers should be optional and thin. They should not alter the
core model, and any method that runs diagnostics should do so visibly from the
method name or parameters. Bound helpers that need a spectrum require either a
materialized `spectrum=...` argument or `run_forward=True`; they should not run a
forward model implicitly.

```python
plots = zp.for_prepared(prepared)

plots.spectrum.reflectance(
    *,
    spectrum=None,
    window_nm=None,
    markers_nm=(),
    run_forward: bool = False,
) -> alt.LayerChart

plots.spectrum.triplet(
    *,
    spectrum=None,
    markers_nm=(755.0, 760.76, 776.0),
    run_forward: bool = False,
) -> alt.VConcatChart

plots.validation.reflectance_residual_report(
    reference,
    *,
    spectrum=None,
    residual_threshold: float = 1.0e-14,
    run_forward: bool = False,
) -> alt.VConcatChart

plots.atmosphere.optical_depth_heatmap(
    *,
    wavelengths_nm: Sequence[float],
    quantity: str = zp.fields.TOTAL_OPTICAL_DEPTH,
    vertical_axis: str = "altitude_km",
) -> alt.Chart

plots.o2_lines.window(
    *,
    spectrum=None,
    wavelengths_nm: Sequence[float] = (760.76,),
    center_nm: float = 760.76,
    max_rows: int = 100_000,
    top_n: int = 40,
    run_forward: bool = False,
) -> alt.VConcatChart

plots.collision_induced_absorption.budget(
    *,
    wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0),
) -> alt.VConcatChart

plots.instrument_response.kernel(
    *,
    wavelengths_nm: Sequence[float] = (760.76,),
    channel: str = "radiance",
) -> alt.LayerChart

plots.radiative_transfer.budget(
    *,
    wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0),
    spectrum=None,
    run_forward: bool = False,
) -> alt.VConcatChart

plots.perturbation.delta_reflectance(
    parameter_path: str,
    value,
    *,
    label: str | None = None,
) -> alt.LayerChart
```

Example direct usage:

```python
import zdisamar as zd
import zdisamar.plot as zp

zp.use_theme("journal")

case = zd.o2a_disamar_reference_input()

with zd.prepare(case) as prepared:
    with prepared.forward_model() as spectrum:
        chart = zp.spectrum.reflectance(
            spectrum,
            markers_nm=[755.0, 760.76, 776.0],
        )
        zp.save(chart, "out/reflectance.svg")

    with prepared.atmosphere.budget(wavelengths_nm=[755.0, 760.76, 776.0]) as budget:
        chart = zp.atmosphere.optical_depth_heatmap(
            budget,
            quantity=zp.fields.TOTAL_OPTICAL_DEPTH,
        )
        zp.save(chart, "out/optical_depth_heatmap.svg")
```

Example bound usage:

```python
with zd.prepare(case) as prepared:
    plots = zp.for_prepared(prepared)

    chart = plots.spectrum.triplet(markers_nm=[755.0, 760.76, 776.0])
    zp.save(chart, "out/forward_summary.svg")

    chart = plots.atmosphere.optical_depth_heatmap(
        wavelengths_nm=[755.0, 760.76, 776.0],
        quantity=zp.fields.TOTAL_OPTICAL_DEPTH,
    )
    zp.save(chart, "out/atmosphere_heatmap.svg")
```

## Scientific Styling Specification

All themes should use a white background, black axes, compact legends, no
rounded cards, no dashboard tiles, and no default chart decorations beyond what
helps scientific reading.

### `validation`

Font family guidance: use a monotype or monospace family, such as Menlo,
Monaco, Consolas, Liberation Mono, or DejaVu Sans Mono. Axis style: black axes,
black tick labels, 16 point labels, 20 point titles. Tick/grid style: Matplotlib
parity grid with light grid lines. Line widths: 1.8 for reference lines, 1.4
for current/result lines, thicker red overlays for residual-threshold
highlights. Reference implementation overlays should be blue dashed lines drawn
above the orange solid `zig implementation` line. Dimensions: 1311 px chart
width before PNG export; tall panels for inspection instead of compressed
strips. Numeric formatting: use real scientific tick labels for radiance,
residuals, and tiny metrics; do not place manual exponent text inside the plot
area. Residual histogram and residual-by-wavelength panels should scale the
displayed residuals to a shared axis exponent, such as `Reflectance residual
(x 10^-14)`, instead of repeating scientific notation on every tick.

### `journal`

Font family guidance: use a conservative serif if available, such as
Times-compatible or Liberation Serif; fall back to a generic serif. Axis style:
black axis lines, black tick labels, 10-11 point labels, 11-12 point titles.
Tick/grid style: outward-feeling ticks where Vega-Lite allows; no vertical grid
by default; very light horizontal grid only when needed. Line widths: 1.2 for
primary lines, 0.8 for secondary or reference lines. Point sizes: 20-35. Default
dimensions: 640 x 260 for single spectral plots; 640 x 160 for residual panels.
Palette: restrained, colorblind-aware, mostly dark tones. Legend placement:
right or top-right, compact, no box. Facet/header styling: small bold header, no
shaded panel header. Export: SVG for papers, PDF when supported, PNG at scale
2-3 for quick reports.

### `monochrome`

Font family guidance: serif or sans-serif, but all marks must survive grayscale
printing. Axis style: black axes, black labels, slightly thicker tick marks.
Tick/grid style: no color-coded reliance; use dashed and dotted line encodings.
Line widths: 1.0-1.4. Point sizes: 24-36 with different shapes. Default
dimensions: 620 x 240. Palette: black plus grays, such as `#000000`, `#404040`,
`#737373`, `#A6A6A6`. Legend placement: right. Facet/header styling: black text
only. Export: preferred for journal appendices and parity reports.

### `labbook`

Font family guidance: compact sans-serif, such as Arial-compatible or Liberation
Sans. Axis style: black axes, 9-10 point labels. Tick/grid style: light grid
allowed in both directions because this theme is for inspection. Line widths:
1.0. Point sizes: 16-25. Default dimensions: 560 x 220. Palette: muted but
distinguishable. Legend placement: top or right, compact. Facet/header styling:
small plain headers. Export: PNG or SVG for notebooks and continuous-integration
artifacts.

### `talk`

Font family guidance: clean sans-serif. Axis style: black axes, 14-16 point
labels, larger titles. Tick/grid style: sparse ticks, minimal grid. Line widths:
2.0 for primary lines, 1.4 for secondary lines. Point sizes: 45-70. Default
dimensions: 900 x 360. Palette: same semantic colors but slightly stronger
contrast. Legend placement: bottom or right, readable from projection.
Facet/header styling: larger headers, fewer facets per slide. Export: SVG for
slides or PNG at scale 2.

Semantic colors:

| Quantity | Default color | Monochrome fallback | Notes |
| --- | --- | --- | --- |
| reflectance | `#111111` | black solid | Primary spectrum should normally be black. |
| radiance | `#1F4E79` | dark gray solid | Keep visually distinct from irradiance. |
| irradiance | `#2F6B3F` | medium gray solid | Avoid bright green. |
| absorption | `#7F1D1D` | black dashed | Use for gas absorption and absorption loss. |
| scattering | `#2A5C7A` | dark gray dotted | Use for Rayleigh/aerosol/cloud scattering. |
| total optical depth | `#222222` | black solid | Use as total line over component stacks. |
| aerosol | `#9C6B1F` | dark gray dash-dot | Ochre/brown, not neon orange. |
| cloud | `#6B6B6B` | medium gray solid | Neutral gray; cloud plots often already have context colors. |
| collision-induced absorption | `#8C3F2D` | black dotted | Rust/brown distinguishes collision-induced absorption from ordinary gas absorption. |
| O2 weak lines | `#4E6E8E` | gray dotted | Muted blue. |
| O2 strong lines | `#111111` | black solid | Strong lines should dominate visually. |
| O2 line mixing | `#6A4C7D` | gray dash-dot | Purple, muted. |
| residual positive | `#8B1A1A` | black above-zero fill or markers | Use diverging zero-centered scales for heatmaps. |
| residual negative | `#1F4E79` | gray below-zero fill or markers | Pair with positive residual color. |

Implementation detail: Altair themes should set `config.background = "white"`,
`view.stroke = "black"`, `axis.domainColor = "black"`, `axis.tickColor =
"black"`, `axis.labelColor = "black"`, `axis.titleColor = "black"`,
`legend.labelFontSize` and `legend.titleFontSize` small, and `range.category`
to the selected theme palette. For residual heatmaps, use a zero-centered
diverging scale; for optical-depth heatmaps, use a restrained single-hue or gray
sequential scale and allow `log_color=True`.

## Implementation Checkpoints

### Phase 0: Tracked Design

- [x] Add this versioned plotting design document.
- [x] Add plotting package ownership notes to `docs/python-bindings.md` or a
  future Python package README once implementation starts.
- [x] Decide whether plotting dependencies are always installed or exposed as a
  Python optional dependency group.

### Phase 1: Package Skeleton And Data Adapters

- [x] Create `python/zdisamar/plot/__init__.py`.
- [x] Add `fields.py` with stable field constants.
- [x] Add `data.py` with `to_dataframe(...)` for `Spectrum`, `DiagnosticTable`,
  NumPy structured arrays, Pandas data frames, mappings, and CSV paths.
- [x] Add `theme.py` with `journal`, `monochrome`, `labbook`, and `talk`.
- [x] Add `io.py` with `save(...)`.
- [x] Add smoke coverage for field constants, dataframe conversion, theme
  registration, chart export, and inspectable generated plot files.
- [x] Add a reusable full-sampled-spectrum context wrapper for generated plot
  artifacts.

### Phase 2: P0 Spectrum And Validation Plots

- [x] `reflectance_spectrum`
- [x] `radiance_spectrum`
- [x] `irradiance_spectrum`
- [x] `spectrum_triplet`
- [x] `model_reference_overlay`
- [x] `spectral_residual`
- [x] `residual_histogram`
- [x] `residual_histogram_report` with full sampled reflectance first,
  residual-threshold highlighting, histogram, residuals-by-wavelength panel,
  neutral reference-implementation labeling, shared residual exponent axis
  labels, and monotype validation styling.
- [x] `validation_metrics_bar`
- [x] `o2a_forward_summary` bundle
- [x] `validation_against_reference` bundle

### Phase 3: P0 Diagnostic Table Plots

- [x] `o2_line_window`
- [x] `o2_line_contribution_stems`
- [x] `o2_line_partition_bar`
- [x] `optical_depth_profile`
- [x] `optical_depth_heatmap`
- [x] `optical_depth_component_stack`
- [x] `aerosol_share_spectrum`
- [x] `cia_share_profile`
- [x] `cia_share_spectrum`
- [x] `instrument_response_kernel`
- [x] `instrument_support_width`
- [x] `rt_source_profile`
- [x] `rt_cumulative_transmission`
- [x] `perturbation_delta_reflectance`
- [x] `perturbation_abs_delta_reflectance`
- [x] `perturbation_summary_bar`

### Phase 4: P1 Plots And Bundles

- [x] `one_to_one_scatter`
- [x] `o2_line_status_counts`
- [x] `o2_isotope_contribution_bar`
- [x] `o2_cross_section_profile`
- [x] `single_scatter_albedo_profile`
- [x] `aerosol_optical_depth_profile`
- [x] `cloud_optical_depth_profile`
- [x] `cloud_share_spectrum`
- [x] `cia_cross_section_temperature`
- [x] `instrument_response_matrix`
- [x] `instrument_weight_rank`
- [x] `rt_proxy_share_bar`
- [x] `perturbation_delta_heatmap`
- [x] `micro_window_marker_spectrum`
- [x] `o2_line_window` bundle
- [x] `atmospheric_budget` bundle
- [x] `collision_induced_absorption_budget` bundle
- [x] `instrument_response` bundle
- [x] `radiative_transfer_budget` bundle
- [x] `perturbation_sensitivity` bundle

### Phase 5: P2 And Future Retrieval-Oriented Plots

- [x] `pseudo_spherical_airmass_profile`
- [ ] `information_content_micro_window`
- [ ] `retrieval_iteration_trace`
- [ ] `spectral_covariance_heatmap`
- [x] Mark required native/Python data contracts for Jacobians,
  covariance/error matrices, and retrieval iterations before implementing P2
  retrieval plots.

### Phase 6: Bound Convenience API

- [x] Add `bound.py` and `zp.for_prepared(prepared)`.
- [x] Ensure bound helpers never silently run an expensive forward model.
- [x] Require bound diagnostic helpers to make diagnostic wavelengths explicit.
- [x] Add tests that direct and bound APIs produce equivalent Altair specs for
  the same materialized inputs.

### Phase 7: Verification And Export

- [ ] Add smoke tests that build every implemented chart and validate its Altair
  spec includes expected x/y fields.
- [ ] Add at least one SVG export smoke test using `vl-convert-python`.
- [ ] Add a generated plot-bundle smoke test analogous to existing Python
  diagnostic harnesses.
- [ ] Add docs examples for direct and bound usage.

## References

- [S1] [GMD - Introduction of the DISAMAR radiative transfer model](https://gmd.copernicus.org/articles/15/7031/2022/)
- [S2] [AMT - Improvements in aerosol layer height retrievals from TROPOMI oxygen A-band measurements by surface albedo fitting in optimal estimation](https://amt.copernicus.org/articles/18/2553/2025/)
- [S3] [AMT - Improved retrievals of carbon dioxide from Orbiting Carbon Observatory-2 with the version 8 ACOS algorithm](https://amt.copernicus.org/articles/11/6539/2018/)
- [S4] [Multispectrum analysis of the oxygen A-band](https://www.osti.gov/pages/biblio/1331969)
- [S5] [NIST - An Accurate Determination of O2 A-band Line Intensities through Experiment and Theory](https://www.nist.gov/publications/accurate-determination-o2-band-line-intensities-through-experiment-and-theory)
- [S6] [HITRANonline data: Collision Induced Absorption](https://hitran.org/cia/)
- [S7] [ACP - FRESCO+: an improved O2 A-band cloud retrieval algorithm](https://acp.copernicus.org/articles/8/6565/2008/acp-8-6565-2008.html)
- [S8] [ACP - The semianalytical cloud retrieval algorithm for SCIAMACHY II](https://acp.copernicus.org/articles/6/4129/2006/)
- [S9] [ACP - Surface pressure retrieval from SCIAMACHY measurements in the O2 A Band](https://acp.copernicus.org/articles/5/2109/2005/)
- [S10] [AMT - Information content of OCO-2 oxygen A-band channels for retrieving marine liquid cloud properties](https://amt.copernicus.org/articles/11/1515/2018/)
- [S11] [AMT - Retrieval of aerosol parameters from the oxygen A band in the presence of chlorophyll fluorescence](https://amt.copernicus.org/articles/6/2725/2013/)
- [S12] [AMT - Error sources in the retrieval of aerosol information over bright surfaces from satellite measurements in the oxygen A band](https://amt.copernicus.org/articles/11/161/2018/)
- [S13] [AMT - A weighted least squares approach to retrieve aerosol layer height over bright surfaces applied to GOME-2 measurements of the oxygen A band](https://amt.copernicus.org/articles/11/3263/2018/)
- [S14] [AMT - In-flight estimation of instrument spectral response functions using sparse representations](https://amt.copernicus.org/articles/18/2573/2025/)
- [S15] [AMT - Determination of the TROPOMI-SWIR instrument spectral response function](https://amt.copernicus.org/articles/11/3917/2018/)
