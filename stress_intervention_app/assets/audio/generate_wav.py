import wave
import struct
import math
import os

# ディレクトリ作成
dir_path = os.path.dirname(os.path.abspath(__file__))
filepath = os.path.join(dir_path, 'relax_music.wav')

# 音源の設定（リラックスできるソフトな音として、低めの周波数 261.63Hz = C4）
sample_rate = 44100.0 # 44.1kHz
duration = 10.0       # 10秒
frequency = 261.63    # C4 (中央Cのド、落ち着いたトーン)
volume = 0.3          # 控えめな音量

num_samples = int(duration * sample_rate)

with wave.open(filepath, 'w') as wav_file:
    wav_file.setparams((1, 2, int(sample_rate), num_samples, 'NONE', 'not compressed'))
    for i in range(num_samples):
        t = i / sample_rate
        # 単一正弦波よりも心地よいように、倍音（Overtone）を少しブレンドして丸みのある音にする
        val = math.sin(2.0 * math.pi * frequency * t) * 0.7
        val += math.sin(2.0 * math.pi * (frequency * 2) * t) * 0.2
        val += math.sin(2.0 * math.pi * (frequency * 3) * t) * 0.1
        
        value = int(volume * 32767.0 * val)
        # クリップ処理
        value = max(-32768, min(32767, value))
        
        data = struct.pack('<h', value)
        wav_file.writeframesraw(data)

print(f"Generated WAV at: {filepath}")
