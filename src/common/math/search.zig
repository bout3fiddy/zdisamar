// search.zig -------------------------------------------------------------------------------------------------|
// Small ordered-search helpers shared by interpolation and sampling code.                                     |
//                                                                                                             |
// boundary                                                                                                    |
//   The helpers assume ascending keys and return indexes only. They do not own data, allocate, clamp, or      |
//   decide interpolation policy for callers.                                                                  |
// ------------------------------------------------------------------------------------------------------------|

pub fn lowerBound(keys: []const f64, target: f64) usize {
    // lowerBound -------------------------------------------------------------------------------------------- |
    // Return the greatest index whose key is <= target in an ascending non-empty key slice.                   |
    //                                                                                                         |
    // caller contract                                                                                         |
    //   keys.len must be non-zero and target must be inside the caller's accepted domain. Values below the    |
    //   first key return 0; values above the last key return keys.len - 1.                                    |
    // --------------------------------------------------------------------------------------------------------|
    var lower_index: usize = 0;
    var upper_index: usize = keys.len - 1;
    while (upper_index - lower_index > 1) {
        const middle_index = lower_index + (upper_index - lower_index) / 2;
        if (keys[middle_index] > target) {
            upper_index = middle_index;
        } else {
            lower_index = middle_index;
        }
    }

    return lower_index;
}

// ------------------------------------------------------------------------------------------------------------|
