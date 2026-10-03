///|
test "increment then decrement returns to zero" {
  let counter = @project_name.Counter::new().increment()
  assert_eq(counter.value(), 1)
  guard counter.decrement() is Some(back) else { fail("expected a value") }
  assert_eq(back.value(), 0)
}

///|
test "decrement at zero is rejected" {
  assert_true(@project_name.Counter::new().decrement() is None)
}
