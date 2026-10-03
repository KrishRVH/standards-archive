///|
/// A count that never drops below zero.
pub struct Counter {
  value : Int
}

///|
pub fn Counter::new() -> Counter {
  { value: 0, }
}

///|
pub fn Counter::value(self : Counter) -> Int {
  self.value
}

///|
pub fn Counter::increment(self : Counter) -> Counter {
  { value: self.value + 1, }
}

///|
/// Returns `None` instead of going below zero.
pub fn Counter::decrement(self : Counter) -> Counter? {
  if self.value == 0 {
    None
  } else {
    Some({ value: self.value - 1, })
  }
}
