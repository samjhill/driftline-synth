# /*****************************************************************************
# * | File        :	  epdconfig.py
# * | Author      :   Waveshare team
# * | Function    :   Hardware underlying interface
# * | Info        :
# *----------------
# * | This version:   V1.2
# * | Date        :   2022-10-29
# * | Info        :   
# ******************************************************************************
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documnetation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to  whom the Software is
# furished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

import os
import logging
import sys
import time
import subprocess

from ctypes import *

logger = logging.getLogger(__name__)


class RaspberryPi:
    # Pin definition
    RST_PIN  = 17
    DC_PIN   = 25
    CS_PIN   = 8
    BUSY_PIN = 24
    PWR_PIN  = 18
    MOSI_PIN = 10
    SCLK_PIN = 11

    def __init__(self):
        import spidev

        self.SPI = spidev.SpiDev()
        self._use_lgpio = False
        self._lgpio = None
        self._lgpio_chip = None
        self._lgpio_out = {}
        self._lgpio_busy = None
        self.GPIO_RST_PIN = None
        self.GPIO_DC_PIN = None
        self.GPIO_PWR_PIN = None
        self.GPIO_BUSY_PIN = None

        try:
            import lgpio

            self._lgpio = lgpio
            chip = lgpio.gpiochip_open(0)
            self._lgpio_chip = chip
            self._lgpio_out[self.RST_PIN] = lgpio.gpio_claim_output(
                chip, self.RST_PIN, lgpio.SET_PULL_NONE, 0
            )
            self._lgpio_out[self.DC_PIN] = lgpio.gpio_claim_output(
                chip, self.DC_PIN, lgpio.SET_PULL_NONE, 0
            )
            self._lgpio_out[self.PWR_PIN] = lgpio.gpio_claim_output(
                chip, self.PWR_PIN, lgpio.SET_PULL_NONE, 0
            )
            self._lgpio_busy = lgpio.gpio_claim_input(
                chip, self.BUSY_PIN, lgpio.SET_PULL_NONE
            )
            self._use_lgpio = True
            logger.debug("epdconfig: using lgpio for HAT pins")
        except Exception as exc:
            logger.debug("epdconfig: lgpio unavailable (%s), falling back to gpiozero", exc)
            import gpiozero

            self.GPIO_RST_PIN = gpiozero.LED(self.RST_PIN)
            self.GPIO_DC_PIN = gpiozero.LED(self.DC_PIN)
            self.GPIO_PWR_PIN = gpiozero.LED(self.PWR_PIN)
            self.GPIO_BUSY_PIN = gpiozero.Button(self.BUSY_PIN, pull_up=False)

    def _lgpio_write(self, pin, value):
        handle = self._lgpio_out.get(pin)
        if handle is not None:
            self._lgpio.gpio_write(self._lgpio_chip, handle, 1 if value else 0)

    def digital_write(self, pin, value):
        if self._use_lgpio:
            if pin in (self.RST_PIN, self.DC_PIN, self.PWR_PIN):
                self._lgpio_write(pin, value)
            return
        if pin == self.RST_PIN:
            if value:
                self.GPIO_RST_PIN.on()
            else:
                self.GPIO_RST_PIN.off()
        elif pin == self.DC_PIN:
            if value:
                self.GPIO_DC_PIN.on()
            else:
                self.GPIO_DC_PIN.off()
        elif pin == self.PWR_PIN:
            if value:
                self.GPIO_PWR_PIN.on()
            else:
                self.GPIO_PWR_PIN.off()

    def digital_read(self, pin):
        if pin == self.BUSY_PIN:
            if self._use_lgpio and self._lgpio_busy is not None:
                return self._lgpio.gpio_read(self._lgpio_chip, self._lgpio_busy)
            return self.GPIO_BUSY_PIN.value
        if self._use_lgpio:
            return 0
        if pin == self.RST_PIN:
            return self.RST_PIN.value
        elif pin == self.DC_PIN:
            return self.DC_PIN.value
        elif pin == self.PWR_PIN:
            return self.PWR_PIN.value

    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)

    def spi_writebyte(self, data):
        self.SPI.writebytes(data)

    def spi_writebyte2(self, data):
        self.SPI.writebytes2(data)

    def DEV_SPI_write(self, data):
        self.DEV_SPI.DEV_SPI_SendData(data)

    def DEV_SPI_nwrite(self, data):
        self.DEV_SPI.DEV_SPI_SendnData(data)

    def DEV_SPI_read(self):
        return self.DEV_SPI.DEV_SPI_ReadData()

    def module_init(self, cleanup=False):
        if self._use_lgpio:
            self._lgpio_write(self.PWR_PIN, 1)
        else:
            self.GPIO_PWR_PIN.on()

        if cleanup:
            find_dirs = [
                os.path.dirname(os.path.realpath(__file__)),
                '/usr/local/lib',
                '/usr/lib',
            ]
            self.DEV_SPI = None
            for find_dir in find_dirs:
                val = int(os.popen('getconf LONG_BIT').read())
                logging.debug("System is %d bit"%val)
                if val == 64:
                    so_filename = os.path.join(find_dir, 'DEV_Config_64.so')
                else:
                    so_filename = os.path.join(find_dir, 'DEV_Config_32.so')
                if os.path.exists(so_filename):
                    self.DEV_SPI = CDLL(so_filename)
                    break
            if self.DEV_SPI is None:
                RuntimeError('Cannot find DEV_Config.so')

            self.DEV_SPI.DEV_Module_Init()

        else:
            # SPI device, bus = 0, device = 0
            self.SPI.open(0, 0)
            self.SPI.max_speed_hz = 4000000
            self.SPI.mode = 0b00
        return 0

    def _lgpio_release(self):
        if not self._use_lgpio or self._lgpio is None or self._lgpio_chip is None:
            return
        chip = self._lgpio_chip
        for handle in list(self._lgpio_out.values()):
            try:
                self._lgpio.gpio_free(chip, handle)
            except Exception:
                pass
        self._lgpio_out.clear()
        if self._lgpio_busy is not None:
            try:
                self._lgpio.gpio_free(chip, self._lgpio_busy)
            except Exception:
                pass
            self._lgpio_busy = None
        try:
            self._lgpio.gpiochip_close(chip)
        except Exception:
            pass
        self._lgpio_chip = None

    def module_exit(self, cleanup=False):
        logger.debug("spi end")
        try:
            self.SPI.close()
        except Exception:
            pass

        if self._use_lgpio:
            self._lgpio_write(self.RST_PIN, 0)
            self._lgpio_write(self.DC_PIN, 0)
            self._lgpio_write(self.PWR_PIN, 0)
            if cleanup:
                self._lgpio_release()
        else:
            self.GPIO_RST_PIN.off()
            self.GPIO_DC_PIN.off()
            self.GPIO_PWR_PIN.off()
            if cleanup:
                self.GPIO_RST_PIN.close()
                self.GPIO_DC_PIN.close()
                self.GPIO_PWR_PIN.close()
                self.GPIO_BUSY_PIN.close()
        logger.debug("close 5V, Module enters 0 power consumption ...")

        



class JetsonNano:
    # Pin definition
    RST_PIN  = 17
    DC_PIN   = 25
    CS_PIN   = 8
    BUSY_PIN = 24
    PWR_PIN  = 18

    def __init__(self):
        import ctypes
        find_dirs = [
            os.path.dirname(os.path.realpath(__file__)),
            '/usr/local/lib',
            '/usr/lib',
        ]
        self.SPI = None
        for find_dir in find_dirs:
            so_filename = os.path.join(find_dir, 'sysfs_software_spi.so')
            if os.path.exists(so_filename):
                self.SPI = ctypes.cdll.LoadLibrary(so_filename)
                break
        if self.SPI is None:
            raise RuntimeError('Cannot find sysfs_software_spi.so')

        import Jetson.GPIO
        self.GPIO = Jetson.GPIO

    def digital_write(self, pin, value):
        self.GPIO.output(pin, value)

    def digital_read(self, pin):
        return self.GPIO.input(self.BUSY_PIN)

    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)

    def spi_writebyte(self, data):
        self.SPI.SYSFS_software_spi_transfer(data[0])

    def spi_writebyte2(self, data):
        for i in range(len(data)):
            self.SPI.SYSFS_software_spi_transfer(data[i])

    def module_init(self):
        self.GPIO.setmode(self.GPIO.BCM)
        self.GPIO.setwarnings(False)
        self.GPIO.setup(self.RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.PWR_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.BUSY_PIN, self.GPIO.IN)
        
        self.GPIO.output(self.PWR_PIN, 1)
        
        self.SPI.SYSFS_software_spi_begin()
        return 0

    def module_exit(self):
        logger.debug("spi end")
        self.SPI.SYSFS_software_spi_end()

        logger.debug("close 5V, Module enters 0 power consumption ...")
        self.GPIO.output(self.RST_PIN, 0)
        self.GPIO.output(self.DC_PIN, 0)
        self.GPIO.output(self.PWR_PIN, 0)

        self.GPIO.cleanup([self.RST_PIN, self.DC_PIN, self.CS_PIN, self.BUSY_PIN, self.PWR_PIN])


class SunriseX3:
    # Pin definition
    RST_PIN  = 17
    DC_PIN   = 25
    CS_PIN   = 8
    BUSY_PIN = 24
    PWR_PIN  = 18
    Flag     = 0

    def __init__(self):
        import spidev
        import Hobot.GPIO

        self.GPIO = Hobot.GPIO
        self.SPI = spidev.SpiDev()

    def digital_write(self, pin, value):
        self.GPIO.output(pin, value)

    def digital_read(self, pin):
        return self.GPIO.input(pin)

    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)

    def spi_writebyte(self, data):
        self.SPI.writebytes(data)

    def spi_writebyte2(self, data):
        # for i in range(len(data)):
        #     self.SPI.writebytes([data[i]])
        self.SPI.xfer3(data)

    def module_init(self):
        if self.Flag == 0:
            self.Flag = 1
            self.GPIO.setmode(self.GPIO.BCM)
            self.GPIO.setwarnings(False)
            self.GPIO.setup(self.RST_PIN, self.GPIO.OUT)
            self.GPIO.setup(self.DC_PIN, self.GPIO.OUT)
            self.GPIO.setup(self.CS_PIN, self.GPIO.OUT)
            self.GPIO.setup(self.PWR_PIN, self.GPIO.OUT)
            self.GPIO.setup(self.BUSY_PIN, self.GPIO.IN)

            self.GPIO.output(self.PWR_PIN, 1)
        
            # SPI device, bus = 0, device = 0
            self.SPI.open(2, 0)
            self.SPI.max_speed_hz = 4000000
            self.SPI.mode = 0b00
            return 0
        else:
            return 0

    def module_exit(self):
        logger.debug("spi end")
        self.SPI.close()

        logger.debug("close 5V, Module enters 0 power consumption ...")
        self.Flag = 0
        self.GPIO.output(self.RST_PIN, 0)
        self.GPIO.output(self.DC_PIN, 0)
        self.GPIO.output(self.PWR_PIN, 0)

        self.GPIO.cleanup([self.RST_PIN, self.DC_PIN, self.CS_PIN, self.BUSY_PIN], self.PWR_PIN)


if sys.version_info[0] == 2:
    process = subprocess.Popen("cat /proc/cpuinfo | grep Raspberry", shell=True, stdout=subprocess.PIPE)
else:
    process = subprocess.Popen("cat /proc/cpuinfo | grep Raspberry", shell=True, stdout=subprocess.PIPE, text=True)
output, _ = process.communicate()
if sys.version_info[0] == 2:
    output = output.decode(sys.stdout.encoding)

_implementation = None


def _impl_class():
    if "Raspberry" in output:
        return RaspberryPi
    if os.path.exists("/sys/bus/platform/drivers/gpio-x3"):
        return SunriseX3
    return JetsonNano


def _get_implementation():
    global _implementation
    if _implementation is None:
        _implementation = _impl_class()()
    return _implementation


def release_implementation() -> None:
    """Release SPI/GPIO so another process can use the HAT."""
    global _implementation
    if _implementation is None:
        return
    try:
        _implementation.module_exit(cleanup=True)
    except Exception:
        logger.debug("epdconfig release failed", exc_info=True)
    _implementation = None


def __getattr__(name):
    cls = _impl_class()
    if hasattr(cls, name):
        value = getattr(cls, name)
        if isinstance(value, int):
            return value
    return getattr(_get_implementation(), name)


### END OF FILE ###
