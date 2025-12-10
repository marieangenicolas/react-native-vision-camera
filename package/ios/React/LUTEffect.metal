#include <metal_stdlib>
using namespace metal;

kernel void lutEffect(texture2d<half, access::read>  inputTexture  [[ texture(0) ]],
                       texture2d<half, access::read>  lutTexture    [[ texture(1) ]],
                       texture2d<half, access::write> outputTexture [[ texture(2) ]],
                       uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height())
        return;
    half4 color = inputTexture.read(gid);
    // Convert color channels to indices (0-63 range for 64x64 blocks)
    int r = int(floor(color.r * 63.999));
    int g = int(floor(color.g * 63.999));
    int b = int(floor(color.b * 63.999));
    // Calculate which 64x64 block to use based on blue channel
    // LUT is arranged as 8 columns x 8 rows = 64 blocks total
    int blockCol = b % 8;  // Column (0-7)
    int blockRow = b / 8;  // Row (0-7)
    // Calculate LUT coordinates
    // Each block is 64x64 pixels, so we offset by block position
    // then add the R,G position within that block
    float lutX = clamp(float(blockCol * 64 + r) + 0.5, 0.0, 511.5);
    float lutY = clamp(float(blockRow * 64 + g) + 0.5, 0.0, 511.5);
    // Sample the LUT
    half4 lutColor = lutTexture.read(uint2(lutX, lutY));
    // Preserve original alpha
    lutColor.a = color.a;
    outputTexture.write(lutColor, gid);
}
