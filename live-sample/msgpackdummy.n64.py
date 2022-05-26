
import random
import msgpack
import socket
import math
import time

dest = ('192.168.3.127', 8934)
len_threshold = 512
sample = {\
    "t": 1234567890, \
    "v": { \
    }\
}

b = msgpack.packb(sample)
print(b)

sample["t"] += 30
sample["v"]["b"] = 0
b += msgpack.packb(sample)

print("size: {}", len(b))

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)



b = b''
i = 0
while True:
    i = i + 1
    t = int(time.time() * 1000.0)
    sample["t"] = t
    print("time: {}", sample["t"])
    v = sample["v"]
    v["a"] = random.randrange(2)
    #v["b"] = random.randrange(2)
    v["b"] = i % 2
    v["z"] = random.randrange(2)
    v["up"] = random.randrange(2)
    v["down"] = random.randrange(2)
    v["left"] = random.randrange(2)
    v["right"] = random.randrange(2)
    
    v["l"] = i % 2
    v["r"] = random.randrange(2)
    
    
    tmp = int(math.cos(t / 1000.0 * 2 * math.pi / 2) * 127)
    if tmp < 0:
        tmp = tmp + 256
    v["stick_x_raw"] = tmp
    
    tmp = int(math.sin(t / 1000.0 * 2 * math.pi / 2) * 127)
    if tmp < 0:
        tmp = tmp + 256
    v["stick_y_raw"] = tmp
    print("{} {}", v["stick_x_raw"], v["stick_y_raw"])
    v["cup"] = random.randrange(2)
    v["cdown"] = random.randrange(2)
    v["cleft"] = random.randrange(2)
    v["cright"] = random.randrange(2)
    
    
    b += msgpack.packb(sample)
    if len(b) > len_threshold:
        print(b)
        print("size: {}", len(b))
        sock.sendto(b, dest)
        b = b''
    
    time.sleep(1.0/15.0)
    #time.sleep(0.008)

sock.close()
