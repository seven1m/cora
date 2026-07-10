# → zig build -Doptimize=ReleaseFast
# → time build/bin/cora --jit examples/fib.rb
# 832040
# build/bin/cora --jit examples/fib.rb  0.06s user 0.00s system 99% cpu 0.069 total

def fib(n)
  if n == 0
    0
  elsif n == 1
    1
  else
    fib(n - 1) + fib(n - 2)
  end
end

puts fib(30)
