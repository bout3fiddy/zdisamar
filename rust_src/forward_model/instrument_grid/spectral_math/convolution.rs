#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    KernelShapeMismatch,
}

pub fn apply(signal: &[f64], kernel: &[f64], output: &mut [f64]) -> Result<(), Error> {
    if signal.len() != output.len() || kernel.is_empty() {
        return Err(Error::KernelShapeMismatch);
    }

    let half_width = kernel.len() / 2;
    for (index, slot) in output.iter_mut().enumerate() {
        let mut acc = 0.0;
        let mut norm = 0.0;

        for (kernel_index, &weight) in kernel.iter().enumerate() {
            let signal_index_signed = index as isize + kernel_index as isize - half_width as isize;
            if signal_index_signed < 0 || signal_index_signed >= signal.len() as isize {
                continue;
            }
            let signal_index = signal_index_signed as usize;
            acc += signal[signal_index] * weight;
            norm += weight;
        }

        *slot = if norm == 0.0 { 0.0 } else { acc / norm };
    }
    Ok(())
}
