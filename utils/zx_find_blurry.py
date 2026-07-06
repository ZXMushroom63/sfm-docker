#!/usr/bin/python3

import cv2
import sys
import pathlib

def find_laplacian_variance(path):
    image = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    if image is None:
        return 0 #silently fail in this case
    
    h, w = image.shape[:2]
    targ_height = 640
    if h > 640:
        aspect_ratio = w / h
        new_width = int(targ_height * aspect_ratio)
        image = cv2.resize(
            image, (new_width, targ_height), interpolation=cv2.INTER_LINEAR
        )
        
    return int(cv2.Laplacian(image, cv2.CV_64F).var() * 10)

if __name__ == "__main__":
    path = ""
    if len(sys.argv) < 3:
        print("Usage: zx_find_blurry.py <min_sharpness> <paths/to/images.png>", file=sys.stderr)
        print("If min sharpness is -1, will instead print the sharpness value of the first image passed to it.")
        sys.exit(1)
        
    min_sharp = int(sys.argv[1])
    if (min_sharp == -1):
        print(f"Sharpness of {sys.argv[2]} is {find_laplacian_variance(sys.argv[2])}")
        sys.exit(0)
    blurry = []
    for path in sys.argv[2:]:
        variance = find_laplacian_variance(path)
        #sys.stderr.write(f"{path} = {variance}\n")
        if (variance < min_sharp):
            sys.stderr.write(f"{path} is blurry (lv={variance})\n")
            blurry.append(path)
    sys.stderr.flush()
    sys.stdout.write(" ".join(blurry) + "\n")
    sys.stdout.flush()