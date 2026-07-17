let maximum_safe = 9_007_199_254_740_991
let minimum_safe = -maximum_safe

let is_safe value = value >= minimum_safe && value <= maximum_safe
let is_nonnegative_safe value = value >= 0 && value <= maximum_safe
