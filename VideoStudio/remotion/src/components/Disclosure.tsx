import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {outlined} from '../theme';
import {Brand} from '../types';
import {GemIcon} from './Icons';

// Full disclosure card for the opening seconds.
export const DisclosureCard: React.FC<{title: string; body: string; durationInFrames: number; brand: Brand}> = ({
	title,
	body,
	durationInFrames,
	brand,
}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const enter = spring({frame, fps, config: {damping: 15, stiffness: 150}});
	const exit = interpolate(frame, [durationInFrames - 6, durationInFrames], [1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	return (
		<div
			style={{
				position: 'absolute',
				left: 60,
				right: 60,
				top: 1404,
				opacity: enter * exit,
				translate: `0 ${(1 - enter) * 80}px`,
			}}
		>
			<div
				style={{
					...outlined(brand.colors.paper, 0),
					position: 'absolute',
					top: -26,
					left: 28,
					fontSize: 30,
					background: brand.colors.danger,
					border: `4px solid ${brand.colors.ink}`,
					borderRadius: 12,
					padding: '4px 16px 7px',
					zIndex: 1,
				}}
			>
				{title}
			</div>
			<div
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: 22,
					background: 'rgba(20,18,31,0.92)',
					border: `5px solid ${brand.colors.primary}`,
					borderRadius: 26,
					padding: '26px 28px 22px',
				}}
			>
				<GemIcon size={64} />
				<div style={{...outlined(brand.colors.paper, 0), fontSize: 38, lineHeight: 1.15}}>{body}</div>
			</div>
		</div>
	);
};

// Small persistent badge for the rest of the video.
export const DisclosureBadge: React.FC<{text: string; brand: Brand}> = ({text, brand}) => {
	const frame = useCurrentFrame();
	const opacity = interpolate(frame, [0, 8], [0, 1], {extrapolateRight: 'clamp'});
	return (
		<div style={{position: 'absolute', top: 1452, left: 0, right: 0, display: 'flex', justifyContent: 'center', opacity}}>
			<div
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: 12,
					background: 'rgba(20,18,31,0.82)',
					border: `3px solid ${brand.colors.primary}`,
					borderRadius: 999,
					padding: '8px 24px 8px 14px',
				}}
			>
				<GemIcon size={38} />
				<span style={{...outlined(brand.colors.paper, 0), fontSize: 30}}>{text}</span>
			</div>
		</div>
	);
};
