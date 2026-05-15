use super::{
    PreparationContext, PreparationInputs, PreparedOpticalState, accumulate, assemble,
    build_absorbers,
};
use crate::{common::errors, input::scene::Scene};

pub fn prepare(
    scene: &Scene,
    inputs: PreparationInputs<'_>,
) -> Result<PreparedOpticalState, errors::Error> {
    let mut context = PreparationContext::init(scene, inputs)?;
    let mut absorbers = build_absorbers(&mut context)?;
    let accumulation = accumulate(&mut context, &mut absorbers)?;
    let mut prepared = assemble(context, absorbers, accumulation);
    prepared.ensure_shared_rtm_geometry_cache()?;
    Ok(prepared)
}
