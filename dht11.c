
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

volatile uint32_t *gpiomem;

#define GPSET0 7
#define GPCLR0 10
#define GPLEV0 13

#define DHT11_TIMEOUT 32000
#define DHT11_TIMEOUT_ERROR -1

static void
gpio_pin_fsel_out(uint8_t pin)
{
    uint8_t idx, shift;

    // Each FSEL register controls 10 pins.  Each pin setting is controlled by
    // 3 bits.  This calculates which register (idx) we need to work with and
    // the shift inside the register to the setting bits.
    idx = pin / 10;
    shift = (pin % 10) * 3;
    gpiomem[idx] = gpiomem[idx] & ~(0b111 << shift) | (0b001 << shift);
}

static void
gpio_pin_fsel_in(uint8_t pin)
{
    uint8_t idx, shift;

    // Each FSEL register controls 10 pins.  Each pin setting is controlled by
    // 3 bits.  This calculates which register (idx) we need to work with and
    // the shift inside the register to the setting bits.
    idx = pin / 10;
    shift = (pin % 10) * 3;
    gpiomem[idx] = gpiomem[idx] & ~(0b111 << shift);
}

static inline void
gpio_pin_set(uint8_t pin)
{
    gpiomem[GPSET0] = 1 << pin;
}

static inline void
gpio_pin_clr(uint8_t pin)
{
    gpiomem[GPCLR0] = 1 << pin;
}

static inline uint32_t
gpio_pin_lev(uint8_t pin)
{
    return gpiomem[GPLEV0] & (1 << pin);
}

static void
os_set_process_priority(int policy, int priority)
{
    struct sched_param sched;
    memset(&sched, 0, sizeof(sched));
    sched.sched_priority = priority;
    sched_setscheduler(0, policy, &sched);
}

static void
sleep_millis(uint32_t millis) {
    struct timespec sleep;
    sleep.tv_sec = millis / 1000;
    sleep.tv_nsec = (millis % 1000) * 1000000L;
    while (clock_nanosleep(CLOCK_MONOTONIC, 0, &sleep, &sleep) && errno == EINTR);
}

static void
wait_millis(uint32_t millis) {
    // Set delay time period.
    struct timeval deltatime;
    deltatime.tv_sec = millis / 1000;
    deltatime.tv_usec = (millis % 1000) * 1000;
    struct timeval walltime;
    // Get current time and add delay to find end time.
    gettimeofday(&walltime, NULL);
    struct timeval endtime;
    timeradd(&walltime, &deltatime, &endtime);
    // Tight loop to waste time (and CPU) until enough time as elapsed.
    while (timercmp(&walltime, &endtime, <)) {
        gettimeofday(&walltime, NULL);
    }
}

int
dht11_gpio_init()
{
    int fd;
    void *mem;
    fd = open("/dev/gpiomem", O_RDWR);
    if (fd < 0) { return -1; }
    mem = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mem == MAP_FAILED) { return -1; }
    gpiomem = (uint32_t*)mem;
    close(fd);
    return 0;
}

int
dht11_sense(uint8_t gpio_pin, uint32_t counts[])
{
    uint32_t count = 0;
    memset(counts, 0, 82 * sizeof(uint32_t));

    gpio_pin_fsel_out(gpio_pin);

    os_set_process_priority(SCHED_FIFO, sched_get_priority_max(SCHED_FIFO));

    // signal to dht11 to request data
    gpio_pin_set(gpio_pin);
    sleep_millis(500);

    gpio_pin_clr(gpio_pin);
    wait_millis(20);

    gpio_pin_fsel_in(gpio_pin);
    for (volatile int i = 0; i < 50; ++i) { }

    while (gpio_pin_lev(gpio_pin)) {
        count++;
        if (count >= DHT11_TIMEOUT) {
            goto timeout_exit;
        }
    }

    for (uint8_t i = 0; i < 82; i = i + 2) {
        count = 0;
        while (!gpio_pin_lev(gpio_pin)) {
            count++;
            if (count >= DHT11_TIMEOUT) {
                goto timeout_exit;
            }
        }
        counts[i] = count;

        count = 0;
        while (gpio_pin_lev(gpio_pin)) {
            count++;
            if (count >= DHT11_TIMEOUT) {
                goto timeout_exit;
            }
        }
        counts[i+1] = count;
    }

    os_set_process_priority(SCHED_OTHER, 0);
    return 0;

timeout_exit:
    os_set_process_priority(SCHED_OTHER, 0);
    return DHT11_TIMEOUT_ERROR;
}
