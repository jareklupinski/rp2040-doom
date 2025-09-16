/*
 * Copyright (c) 2021 Arm Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 * 
 */

#include <string.h>

#include "hardware/gpio.h"
#include "pico/stdlib.h"

#include "pico/st7789.h"

static struct st7789_config st7789_cfg;
static uint16_t st7789_width;
static uint16_t st7789_height;
static bool st7789_data_mode = false;

static void st7789_cmd(uint8_t cmd, const uint8_t* data, size_t len)
{
    // BSP always uses CPOL_1, CPHA_1 mode
    spi_set_format(st7789_cfg.spi, 8, SPI_CPOL_1, SPI_CPHA_1, SPI_MSB_FIRST);
    st7789_data_mode = false;

    sleep_us(1);
    if (st7789_cfg.gpio_cs > -1) {
        gpio_put(st7789_cfg.gpio_cs, 0);
    }
    gpio_put(st7789_cfg.gpio_dc, 0);
    sleep_us(1);
    
    spi_write_blocking(st7789_cfg.spi, &cmd, sizeof(cmd));
    
    if (len) {
        sleep_us(1);
        gpio_put(st7789_cfg.gpio_dc, 1);
        sleep_us(1);
        
        spi_write_blocking(st7789_cfg.spi, data, len);
    }

    sleep_us(1);
    if (st7789_cfg.gpio_cs > -1) {
        gpio_put(st7789_cfg.gpio_cs, 1);
    }
    gpio_put(st7789_cfg.gpio_dc, 1);
    sleep_us(1);
}

void st7789_caset(uint16_t xs, uint16_t xe)
{
    uint8_t data[] = {
        xs >> 8,
        xs & 0xff,
        xe >> 8,
        xe & 0xff,
    };

    // CASET (2Ah): Column Address Set
    st7789_cmd(0x2a, data, sizeof(data));
}

void st7789_raset(uint16_t ys, uint16_t ye)
{
    uint8_t data[] = {
        ys >> 8,
        ys & 0xff,
        ye >> 8,
        ye & 0xff,
    };

    // RASET (2Bh): Row Address Set
    st7789_cmd(0x2b, data, sizeof(data));
}

void st7789_init(const struct st7789_config* config, uint16_t width, uint16_t height)
{
    memcpy(&st7789_cfg, config, sizeof(st7789_cfg));
    st7789_width = width;
    st7789_height = height;

    spi_init(st7789_cfg.spi, 80 * 1000 * 1000);
    // BSP always uses CPOL_1, CPHA_1 mode regardless of CS pin
    spi_set_format(st7789_cfg.spi, 8, SPI_CPOL_1, SPI_CPHA_1, SPI_MSB_FIRST);

    gpio_set_function(st7789_cfg.gpio_din, GPIO_FUNC_SPI);
    gpio_set_function(st7789_cfg.gpio_clk, GPIO_FUNC_SPI);

    if (st7789_cfg.gpio_cs > -1) {
        gpio_init(st7789_cfg.gpio_cs);
    }
    gpio_init(st7789_cfg.gpio_dc);
    gpio_init(st7789_cfg.gpio_rst);
    gpio_init(st7789_cfg.gpio_bl);

    if (st7789_cfg.gpio_cs > -1) {
        gpio_set_dir(st7789_cfg.gpio_cs, GPIO_OUT);
    }
    gpio_set_dir(st7789_cfg.gpio_dc, GPIO_OUT);
    gpio_set_dir(st7789_cfg.gpio_rst, GPIO_OUT);
    gpio_set_dir(st7789_cfg.gpio_bl, GPIO_OUT);

    if (st7789_cfg.gpio_cs > -1) {
        gpio_put(st7789_cfg.gpio_cs, 1);
    }
    gpio_put(st7789_cfg.gpio_dc, 1);
    
    // Hardware reset sequence matching BSP
    gpio_put(st7789_cfg.gpio_rst, 0);
    sleep_ms(50);
    gpio_put(st7789_cfg.gpio_rst, 1);
    sleep_ms(50);
    
    // Use BSP initialization sequence that works
    // DISPON (29h): Display On 
    st7789_cmd(0x29, NULL, 0);
    sleep_ms(10);
    
    // SLPOUT (11h): Sleep Out
    st7789_cmd(0x11, NULL, 0);
    sleep_ms(10);
    
    // MADCTL (36h): Memory Data Access Control - BSP uses 0x00
    st7789_cmd(0x36, (uint8_t[]){ 0x00 }, 1);

    // COLMOD (3Ah): Interface Pixel Format - BSP uses 0x05
    st7789_cmd(0x3A, (uint8_t[]){ 0x05 }, 1);

    // Power and display control registers from BSP
    st7789_cmd(0xB0, (uint8_t[]){ 0x00, 0xE8 }, 2); // 5 to 6-bit conversion: r0 = r5, b0 = b5

    st7789_cmd(0xB2, (uint8_t[]){ 0x0C, 0x0C, 0x00, 0x33, 0x33 }, 5);

    st7789_cmd(0xB7, (uint8_t[]){ 0x75 }, 1); // VGH=14.97V,VGL=-7.67V

    st7789_cmd(0xBB, (uint8_t[]){ 0x1A }, 1);

    st7789_cmd(0xC0, (uint8_t[]){ 0x2C }, 1);

    st7789_cmd(0xC2, (uint8_t[]){ 0x01, 0xFF }, 2);

    st7789_cmd(0xC3, (uint8_t[]){ 0x13 }, 1);

    st7789_cmd(0xC4, (uint8_t[]){ 0x20 }, 1);

    st7789_cmd(0xC6, (uint8_t[]){ 0x0F }, 1);

    st7789_cmd(0xD0, (uint8_t[]){ 0xA4, 0xA1 }, 2);

    st7789_cmd(0xD6, (uint8_t[]){ 0xA1 }, 1);

    // Gamma correction positive
    st7789_cmd(0xE0, (uint8_t[]){ 0xD0, 0x0D, 0x14, 0x0D, 0x0D, 0x09, 0x38, 0x44, 0x4E, 0x3A, 0x17, 0x18, 0x2F, 0x30 }, 14);

    // Gamma correction negative  
    st7789_cmd(0xE1, (uint8_t[]){ 0xD0, 0x09, 0x0F, 0x08, 0x07, 0x14, 0x37, 0x44, 0x4D, 0x38, 0x15, 0x16, 0x2C, 0x2E }, 14);

    // INVON (21h): Display Inversion On
    st7789_cmd(0x21, NULL, 0);

    // DISPON (29h): Display On
    st7789_cmd(0x29, NULL, 0);

    // RAMWR (2Ch): Memory Write - prepare for pixel data
    st7789_cmd(0x2C, NULL, 0);

    gpio_put(st7789_cfg.gpio_bl, 1);
}

void st7789_ramwr()
{
    sleep_us(1);
    if (st7789_cfg.gpio_cs > -1) {
        gpio_put(st7789_cfg.gpio_cs, 0);
    }
    gpio_put(st7789_cfg.gpio_dc, 0);
    sleep_us(1);

    // RAMWR (2Ch): Memory Write
    uint8_t cmd = 0x2c;
    spi_write_blocking(st7789_cfg.spi, &cmd, sizeof(cmd));

    sleep_us(1);
    if (st7789_cfg.gpio_cs > -1) {
        gpio_put(st7789_cfg.gpio_cs, 0);
    }
    gpio_put(st7789_cfg.gpio_dc, 1);
    sleep_us(1);
}

void st7789_write(const void* data, size_t len)
{
    if (!st7789_data_mode) {
        st7789_ramwr();

        // BSP always uses CPOL_1, CPHA_1 mode
        spi_set_format(st7789_cfg.spi, 16, SPI_CPOL_1, SPI_CPHA_1, SPI_MSB_FIRST);

        st7789_data_mode = true;
    }

    spi_write16_blocking(st7789_cfg.spi, data, len / 2);
}

void st7789_put(uint16_t pixel)
{
    st7789_write(&pixel, sizeof(pixel));
}

void st7789_fill(uint16_t pixel)
{
    int num_pixels = st7789_width * st7789_height;

    st7789_set_cursor(0, 0);

    for (int i = 0; i < num_pixels; i++) {
        st7789_put(pixel);
    }
}

void st7789_set_cursor(uint16_t x, uint16_t y)
{
    st7789_caset(x, st7789_width);
    st7789_raset(y, st7789_height);
}

void st7789_vertical_scroll(uint16_t row)
{
    uint8_t data[] = {
        (row >> 8) & 0xff,
        row & 0x00ff
    };

    // VSCSAD (37h): Vertical Scroll Start Address of RAM 
    st7789_cmd(0x37, data, sizeof(data));
}

void st7789_partial_area(uint16_t start, uint16_t end)
{
    uint8_t data[] = {
        (start >> 8) & 0xff,
        start & 0x00ff,
        (end >> 8) & 0xff,
        end & 0x00ff,
    };

    // PTLAR (30h): Partial Area
    st7789_cmd(0x30, data, sizeof(data));
    // PTLON (12h): Partial Display Mode On
    st7789_cmd(0x12, NULL, 0);
}
