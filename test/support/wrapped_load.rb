WRAPPED_CONSTANT = 9
module WrappedMethods
  def wrapped_method
    17
  end
end
$wrapped_module = WrappedMethods
include WrappedMethods
$wrapped_receiver = self
$wrapped_nesting = Module.nesting
$wrapped_special = wrapped_load_special
