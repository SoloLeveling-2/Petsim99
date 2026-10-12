import {CalculateMetadataFunction, Composition} from 'remotion';
import {ShortOverlay} from './ShortOverlay';
import {OverlayProps} from './types';
import {sampleProps} from './sample-props';

// The render pipeline passes the edit plan as --props; duration and size come from it.
const calculateMetadata: CalculateMetadataFunction<OverlayProps> = ({props}) => {
	return {
		durationInFrames: Math.max(1, Math.ceil(props.duration * props.fps)),
		fps: props.fps,
		width: props.width,
		height: props.height,
	};
};

export const RemotionRoot = () => {
	return (
		<Composition
			id="ShortOverlay"
			component={ShortOverlay}
			durationInFrames={600}
			fps={30}
			width={1080}
			height={1920}
			defaultProps={sampleProps}
			calculateMetadata={calculateMetadata}
		/>
	);
};
