import {Config} from '@remotion/cli/config';

// Transparent overlay frames: PNG keeps the alpha channel for FFmpeg to composite.
Config.setVideoImageFormat('png');
Config.setOverwriteOutput(true);
