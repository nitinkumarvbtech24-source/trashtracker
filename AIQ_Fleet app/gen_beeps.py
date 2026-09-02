import wave, math, struct, base64

def gen_beep(freq, duration_ms, filename):
    sample_rate = 44100
    n_samples = int(sample_rate * (duration_ms / 1000.0))
    with wave.open(filename, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        for i in range(n_samples):
            value = int(32767.0*math.sin(2.0*math.pi*freq*i/sample_rate))
            w.writeframesraw(struct.pack('<h', value))

gen_beep(1000, 100, 'beep_high.wav')
gen_beep(500, 150, 'beep_low.wav')
gen_beep(1500, 50, 'click.wav')

print('BEEP_HIGH:', base64.b64encode(open('beep_high.wav', 'rb').read()).decode('utf-8'))
print('BEEP_LOW:', base64.b64encode(open('beep_low.wav', 'rb').read()).decode('utf-8'))
print('CLICK:', base64.b64encode(open('click.wav', 'rb').read()).decode('utf-8'))
