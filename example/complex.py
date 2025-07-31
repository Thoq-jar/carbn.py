print("=== Prime Number Generator & Analysis ===")

limit = 50
primes_found = 0
sum_of_primes = 0

print("Finding prime numbers up to")
print(limit)
print("")

for num in range(2, limit):
    is_prime = 1

    divisor = 2
    while divisor * divisor <= num:
        if num % divisor == 0:
            is_prime = 0
        divisor = divisor + 1

    if is_prime == 1:
        print("Prime found:")
        print(num)
        primes_found = primes_found + 1
        sum_of_primes = sum_of_primes + num

print("")
print("=== Prime Analysis Results ===")
print("Total primes found:")
print(primes_found)
print("Sum of all primes:")
print(sum_of_primes)

if primes_found > 0:
    average = sum_of_primes / primes_found
    print("Average prime value:")
    print(average)

print("")
print("=== Fibonacci Sequence Generator ===")

fib_limit = 15
a = 0
b = 1
fib_count = 0
fib_sum = 0

print("Fibonacci numbers:")
print(a)
print(b)
fib_sum = a + b

while b < fib_limit:
    next_fib = a + b
    if next_fib < fib_limit:
        print(next_fib)
        fib_sum = fib_sum + next_fib
        fib_count = fib_count + 1
    a = b
    b = next_fib

print("Sum of Fibonacci numbers:")
print(fib_sum)

print("")
print("=== Mathematical Calculations ===")

base = 5
power = 3
result = 1

for i in range(0, power):
    result = result * base

print("5 to the power of 3:")
print(result)

factorial_num = 6
factorial_result = 1

for i in range(1, factorial_num + 1):
    factorial_result = factorial_result * i

print("Factorial of 6:")
print(factorial_result)

mod_base = 17
mod_divisor = 5
remainder = mod_base % mod_divisor

print("17 mod 5 equals:")
print(remainder)

print("")
print("=== Pattern Generation ===")

table_size = 7

for i in range(1, table_size):
    for j in range(1, table_size):
        product = i * j
        print(product)
    print("---")

print("")
print("=== Conditional Logic Tests ===")

test_value = 42

if test_value > 50:
    print("Value is large")
else:
    if test_value > 25:
        print("Value is medium")
        if test_value % 2 == 0:
            print("And it's even!")
        else:
            print("And it's odd!")
    else:
        print("Value is small")

x = 10
y = 20
z = 15

if x < y and y > z:
    print("Logical AND test passed")

if x > y or z < y:
    print("Logical OR test passed")

print("")
print("=== Number Sequence Analysis ===")

sequence_sum = 0
even_count = 0
odd_count = 0

for num in range(1, 21):
    sequence_sum = sequence_sum + num

    if num % 2 == 0:
        even_count = even_count + 1
    else:
        odd_count = odd_count + 1

    if num % 5 == 0:
        print("Milestone reached:")
        print(num)

print("Final sequence statistics:")
print("Sum of 1 to 20:")
print(sequence_sum)
print("Even numbers count:")
print(even_count)
print("Odd numbers count:")
print(odd_count)

print("")
print("=== Complex Nested Operations ===")

outer_sum = 0

for i in range(1, 6):
    inner_sum = 0
    for j in range(1, 4):
        calculation = i * j + j * j
        inner_sum = inner_sum + calculation

    print("Inner sum for i =")
    print(i)
    print("equals:")
    print(inner_sum)

    outer_sum = outer_sum + inner_sum

print("Total outer sum:")
print(outer_sum)

print("")
print("=== Program Complete ===")
print("All calculations finished successfully!")
