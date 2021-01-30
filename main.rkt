#lang racket/base

(require racket/runtime-path
         ffi/unsafe
         syntax/parse/define)

(provide (rename-out
           [dht11_gpio_init dht11-init])

         exn:dht11?

         exn:dht11:init-error?
         exn:dht11:init-error-errno

         exn:dht11:sense-timeout?
         exn:dht11:sense-timeout-counts

         exn:dht11:checksum-fail?
         exn:dht11:checksum-fail-bytes
         exn:dht11:checksum-fail-checksum

         dht11-current-humidity/temperature)

(define-runtime-path libdht11-path "libdht11")

(define dht11-lib
  (ffi-lib libdht11-path))

(struct exn:dht11 exn:fail () #:transparent)
(struct exn:dht11:init-error    exn:dht11 (errno)  #:transparent)
(struct exn:dht11:sense-timeout exn:dht11 (counts) #:transparent)
(struct exn:dht11:checksum-fail exn:dht11 (bytes checksum) #:transparent)

(define dht11_gpio_init
  (get-ffi-obj
    "dht11_gpio_init"
    dht11-lib
    (_fun #:save-errno 'posix 
          -> [rc : _int]
          -> (unless (zero? rc)
               (raise 
                 (exn:dht11:init-error
                   "error initializing dht11 foreign library"
                   (current-continuation-marks)
                   (saved-errno)))))))

(define dht11_sense
  (get-ffi-obj
    "dht11_sense"
    dht11-lib
    ;; XXX: lock-name should include the pin number
    (_fun #:lock-name "dht11"
          #:blocking? #t
          _uint8
          [counts : (_ptr o (_array _uint32 82))]
          -> [rc : _int]
          -> (cond
               [(zero? rc) counts]
               [else
                 (raise
                   (exn:dht11:sense-timeout
                     "timeout reading from dht11 sensor"
                     (current-continuation-marks)
                     counts))]))))

(define (signal->values counts)
  (define low-duration
    (for/fold ([sum 0] [count 0] #:result (/ sum count))
              ([low (in-array counts 2 82 2)])
      (values (+ sum low) (add1 count))))

  (define-simple-macro (define-signal-value name:id
                                            start:exact-positive-integer
                                            end:exact-positive-integer)
    (define name
      (for/fold ([v 0]) ([hi (in-array counts start end 2)])
        ((if (> hi low-duration) add1 values) 
         (arithmetic-shift v 1)))))

  (define-signal-value humidity-int      3 18)
  (define-signal-value humidity-frac    19 34)
  (define-signal-value temperature-int  35 50)
  (define-signal-value temperature-frac 51 66)
  (define-signal-value checksum         67 82)

  (values humidity-int
          humidity-frac
          temperature-int
          temperature-frac
          checksum))

(define (dht11-current-humidity/temperature gpio-pin)
  (define counts (dht11_sense gpio-pin))
  (define-values (humid-int humid-frac
                  temp-int  temp-frac
                  checksum)
    (signal->values counts))

  (let ([sum (bitwise-and #xff (+ humid-int humid-frac temp-int temp-frac))])
    (unless (= sum checksum)
      (raise
        (exn:dht11:checksum-fail
          (format "current-humidity/temperature: checksum failed\n values: ~a\n checksum: ~a\n expected: ~a\n"
                  (list humid-int humid-frac temp-int temp-frac)
                  sum checksum)
          (current-continuation-marks)
          (list humid-int humid-frac temp-int temp-frac)
          checksum))))

  (values (+ humid-int (/ humid-frac 256))
          (+ temp-int  (/ temp-frac  256))))

(module* main #f
  (require racket/format
           racket/match)

  (define gpio-pin
    (match (current-command-line-arguments)
      [(vector (app string->number (? number? gpio-pin))) gpio-pin]
      [x (error 'main "expected gpio pin number got: ~a" x)]))

  (dht11_gpio_init)

  (define start   (current-seconds))
  (define success 0)
  (define fail    0)

  (define (error-handler e)
    (parameterize ([current-error-port (current-output-port)])
      ((error-display-handler) (exn-message e) e))
    (set! fail (add1 fail))
    (sleep 5))

  (define (run)
    (with-handlers ([exn:dht11? error-handler])
      (define-values (h t) (dht11-current-humidity/temperature gpio-pin))
      (set! success (add1 success))
      (displayln (~a "[" (current-seconds) "] "
                     "[" (- (current-seconds) start) "/" success "/" fail "] "
                     "H: " (~r h #:precision '(= 1)) "% "
                     "T: " (~r t #:precision '(= 1)) "C")))
    (flush-output)
    (sleep 15)
    (run))

  (run))
