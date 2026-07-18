# plumOS V90S Boot Logo

`bootlogo.png` is the editable 640x480 source image. `bootlogo.bmp` is the
bootloader-ready asset copied to `PLUMBOOT:/bootlogo.bmp` by the four-partition
image assembler.

The V90S bootloader contract is a Windows 3.x, 640x480, 24-bit, uncompressed
BMP. Regenerate the BMP with ImageMagick:

```sh
magick bootlogo.png -background black -alpha remove -alpha off \
  -colorspace sRGB -type TrueColor BMP3:bootlogo.bmp
```

Validate it before building an image:

```sh
python3 scripts/verify-v90s-boot-logo.py package/boot-assets-v90s/bootlogo.bmp
```
