#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum CloudType {
    #[default]
    None,
    LambWavelIndep,
    Lambertian,
    MieScattering,
    HgScattering,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum AerosolType {
    #[default]
    None,
    LambWavelIndep,
    Lambertian,
    MieScattering,
    HgScattering,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AbsorberSpecies {
    O2O2,
    O2,
}

impl AbsorberSpecies {
    pub fn is_line_absorbing(self) -> bool {
        matches!(self, Self::O2)
    }

    pub fn is_cross_section(self) -> bool {
        matches!(self, Self::O2O2)
    }

    pub fn is_column_fittable(self) -> bool {
        false
    }

    pub fn is_profile_fittable(self) -> bool {
        self.is_column_fittable()
    }

    pub fn hitran_index(self) -> Option<u8> {
        match self {
            // DISAMAR uses the HITRAN molecule number for line absorption lookup.
            Self::O2 => Some(7),
            Self::O2O2 => None,
        }
    }

    pub fn from_vendor_name(name: &str) -> Option<Self> {
        match name {
            "O2-O2" => Some(Self::O2O2),
            "O2" => Some(Self::O2),
            _ => None,
        }
    }
}
