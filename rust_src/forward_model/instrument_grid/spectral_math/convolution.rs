#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    KernelShapeMismatch,
}

pub type Result<T> = std::result::Result<T, Error>;

pub fn apply(signal: &[f64], kernel: &[f64], output: &mut [f64]) -> Result<()> {
    if signal.len() != output.len() || kernel.is_empty() {
        return Err(Error::KernelShapeMismatch);
    }

    let half_width = kernel.len() / 2;
    for (index, slot) in output.iter_mut().enumerate() {
        let mut acc = 0.0;
        let mut norm = 0.0;

        for (kernel_index, &weight) in kernel.iter().enumerate() {
            let signal_index = index as isize + kernel_index as isize - half_width as isize;
            if signal_index < 0 || signal_index >= signal.len() as isize {
                continue;
            }
            acc += signal[signal_index as usize] * weight;
            norm += weight;
        }

        *slot = if norm == 0.0 { 0.0 } else { acc / norm };
    }
    Ok(())
}
