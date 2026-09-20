import subprocess, sys
def load(path):
    w,h = map(int, subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0","-show_entries","stream=width,height","-of","csv=p=0",path]).decode().strip().split(","))
    raw = subprocess.check_output(["ffmpeg","-v","error","-i",path,"-f","rawvideo","-pix_fmt","rgb24","-"])
    return w,h,raw
def col(path, x, y0, y1, label):
    w,h,raw = load(path)
    print(f"== {label} {path} x={x} (px @2x)  y: r g b  |lum")
    for y in range(y0, y1):
        i = (y*w + x)*3; r,g,b = raw[i], raw[i+1], raw[i+2]
        lum = int(0.3*r+0.59*g+0.11*b)
        mark = "#"*(lum//6)
        print(f"{y:4d}: {r:3d} {g:3d} {b:3d} |{lum:3d} {mark}")
path, x, y0, y1, label = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
col(path, x, y0, y1, label)
