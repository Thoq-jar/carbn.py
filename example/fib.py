def fib(n):
    if n < 2:
        return n
    else:
        return fib(n-1) + fib(n-2)

for i in range(0, 184):
    print(f"fib: {i} = {fib(i)}")
