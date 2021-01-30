# Racket DHT11 Library

Code for interfacing to a DHT11 sensor on a Raspberry Pi with [Racket][1]

This is fairly stable right now.  Obviously I haven't packaged it up (yet!) so
you will have to do that on your own.  This has been tested on a Raspberry Pi
4, running Ubuntu 20.10 with Racket 7.9 [cs].

# Basic Design

I took the conservative route and implemented the part that reads the pin
states in C.  It's mostly a translation of an [Adafruit Python C module][2] I
found on github.  Basically Racket calls into a C function that fills a uint
array with "timings" of zeroes and ones.  Then on the Racket side there is code
that converts that into bytes.  Basically trying to do the least amount of work
that needs to be done in C.

# Typical Setup

When the C code is running the Racket runtime will be blocked.  To avoid this
run a sensor polling process in a separate place and communicate the sensor
values to a place where the main application work is going to occur.

# "Issues"

- [ ] Not packaged
- [ ] Need to confirm that FFI callout locks are (or not) system-wide global.
      This effects if different Racket processes using the library can conflict
      with each other.  Still other programs that don't follow some kind of
      locking protocol can still cause problems.
- [ ] FFI callout lock name should be unique for each GPIO pin so in theory
      multiple sensors could be used.
- [ ] Are the number of timeouts and checksum errors normal or too much?  I get a fair
      number but it seems acceptable around < 20%.

[1]: https://www.racket-lang.org/
[2]: https://github.com/adafruit/Adafruit_Python_DHT
