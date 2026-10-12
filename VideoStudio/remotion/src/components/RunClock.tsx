import React from 'react';
import {interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {formatClock, outlined} from '../theme';
import {Brand, ClockKey, Rect} from '../types';
import {ClockIcon, FastForwardIcon} from './Icons';

// Source time at output time t. Keys come in (start, end) pairs per segment; during a
// crossfade the later segment wins.
export const sourceTimeAt = (keys: ClockKey[], t: number) => {
	let best: number | null = null;
	for (let i = 0; i + 1 < keys.length; i += 2) {
		const a = keys[i];
		const b = keys[i + 1];
		if (a.t <= t && t <= b.t) {
			best = interpolate(t, [a.t, b.t], [a.src_t, b.src_t]);
		}
	}
	return best;
};

// Shows how far into the real recording each moment is, so cuts and time-lapses stay honest.
export const RunClock: React.FC<{
	keys: ClockKey[];
	speedups: {start: number; end: number; speed: number}[];
	start: number;
	main: Rect;
	brand: Brand;
}> = ({keys, speedups, start, main, brand}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const t = start + frame / fps;
	const src = sourceTimeAt(keys, t);
	const fast = speedups.find((s) => s.start <= t && t <= s.end);
	const opacity = interpolate(frame, [0, 8], [0, 1], {extrapolateRight: 'clamp'});
	if (src === null) return null;
	return (
		<div
			style={{
				position: 'absolute',
				right: 1080 - (main.x + main.w) + 28,
				top: main.y + 30,
				display: 'flex',
				flexDirection: 'column',
				alignItems: 'flex-end',
				gap: 10,
				opacity,
			}}
		>
			<div
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: 12,
					background: 'rgba(20,18,31,0.8)',
					border: `4px solid ${brand.colors.paper}`,
					borderRadius: 999,
					padding: '8px 22px 8px 12px',
				}}
			>
				<ClockIcon size={44} />
				<span style={{...outlined(brand.colors.paper, 0), fontSize: 44, fontVariantNumeric: 'tabular-nums'}}>
					{formatClock(src)}
				</span>
			</div>
			<span style={{...outlined(brand.colors.paper, 6, brand.colors.ink), fontSize: 24}}>INTO THE RECORDING</span>
			{fast ? (
				<div
					style={{
						display: 'flex',
						alignItems: 'center',
						gap: 8,
						background: brand.colors.accent,
						border: `4px solid ${brand.colors.ink}`,
						borderRadius: 14,
						padding: '4px 14px 6px',
					}}
				>
					<FastForwardIcon size={30} />
					<span style={{...outlined(brand.colors.ink, 0), fontSize: 34}}>{fast.speed}x SPEED</span>
				</div>
			) : null}
		</div>
	);
};
