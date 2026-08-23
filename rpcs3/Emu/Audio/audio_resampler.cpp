#include "stdafx.h"
#include "Emu/Audio/audio_resampler.h"
#include <algorithm>

audio_resampler::audio_resampler()
{
	// This resampler sits inside the emulated audio path, so the delay it holds internally is part
	// of the latency cellAudio's buffering algorithm is trying to control - and it cannot see it,
	// because get_enqueued_samples() only counts samples SoundTouch has already produced. Long
	// WSOLA windows therefore both add delay and make the tempo control loop overshoot, on top of
	// smearing transients across the splice. Keep the windows short.
	resampler.setSetting(SETTING_SEQUENCE_MS, 20);
	resampler.setSetting(SETTING_SEEKWINDOW_MS, 8);
	resampler.setSetting(SETTING_OVERLAP_MS, 4);

	// The full correlation search runs on the audio thread and costs several times what quick seek
	// does. Starving that thread into an underrun is far more audible than the marginally worse
	// splice point quick seek settles for at the sub-percent tempo corrections used here.
	resampler.setSetting(SETTING_USE_QUICKSEEK, 1);

	// Only the tempo is ever changed (see set_tempo), the sample rate is left untouched, so the rate
	// transposer this filter belongs to is bypassed and the filter would only burn cycles.
	resampler.setSetting(SETTING_USE_AA_FILTER, 0);
}

audio_resampler::~audio_resampler()
{
}

void audio_resampler::set_params(AudioChannelCnt ch_cnt, AudioFreq freq)
{
	flush();
	resampler.setChannels(static_cast<u32>(ch_cnt));
	resampler.setSampleRate(static_cast<u32>(freq));
}

f64 audio_resampler::set_tempo(f64 new_tempo)
{
	new_tempo = std::clamp(new_tempo, RESAMPLER_MIN_FREQ_VAL, RESAMPLER_MAX_FREQ_VAL);
	resampler.setTempo(new_tempo);
	return new_tempo;
}

void audio_resampler::put_samples(const f32* buf, u32 sample_cnt)
{
	resampler.putSamples(buf, sample_cnt);
}

std::pair<f32* /* buffer */, u32 /* samples */> audio_resampler::get_samples(u32 sample_cnt)
{
	// NOTE: Make sure to get the buffer first because receiveSamples advances its position internally
	//       and std::make_pair evaluates the second parameter first...
	f32* const buf = resampler.bufBegin();
	return std::make_pair(buf, resampler.receiveSamples(sample_cnt));
}

u32 audio_resampler::samples_available() const
{
	return resampler.numSamples();
}

f64 audio_resampler::get_resample_ratio()
{
	return resampler.getInputOutputSampleRatio();
}

void audio_resampler::flush()
{
	resampler.clear();
}
