# Copies the switches to the LEDs forever. Used by test_Wrapper_DIP_to_LED_self_checking.v.
.eqv MMIO_BASE 0xFFFF0000
.text
    li   s0, MMIO_BASE
loop:
    lw   t0, 0x64(s0)
    sw   t0, 0x60(s0)
    jal  x0, loop
