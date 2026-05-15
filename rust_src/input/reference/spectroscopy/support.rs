use crate::input::reference_data::SpectroscopyLine;

pub fn line_has_vendor_strong_line_metadata(line: &SpectroscopyLine) -> bool {
    line.branch_ic1.is_some() && line.branch_ic2.is_some() && line.rotational_nf.is_some()
}

pub fn line_has_vendor_strong_line_metadata_from_source(line: &SpectroscopyLine) -> bool {
    line.vendor_filter_metadata_from_source && line_has_vendor_strong_line_metadata(line)
}

pub fn is_vendor_o2a_strong_candidate(line: &SpectroscopyLine) -> bool {
    line.gas_index == 7
        && line.isotope_number == 1
        && line.branch_ic1 == Some(5)
        && line.branch_ic2 == Some(1)
        && line.rotational_nf.is_some_and(|value| value <= 35)
}

pub fn is_vendor_o2a_strong_candidate_from_source(line: &SpectroscopyLine) -> bool {
    line.vendor_filter_metadata_from_source && is_vendor_o2a_strong_candidate(line)
}
