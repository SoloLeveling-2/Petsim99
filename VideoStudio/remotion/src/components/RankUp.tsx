import React from 'react';
import {interpolate, random, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {outlined} from '../theme';
import {Brand, Rect} from '../types';

const CONFETTI = ['#FFC83D', '#3DDC97', '#7C5CFF', '#FF4D6D', '#4FD1FF'];

export const RankUp: React.FC<{durationInFrames: number; main: Rect; brand: Brand}> = ({durationInFrames, main, brand}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const enter = spring({frame, fps, config: {damping: 8, stiffness: 160}});
	const exit = interpolate(frame, [durationInFrames - 10, durationInFrames], [1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	const cy = main.y + 210;
	return (
		<div style={{position: 'absolute', inset: 0, opacity: exit}}>
			<svg
				width={1080}
				height={700}
				style={{position: 'absolute', left: 0, top: cy - 350, rotate: `${frame * 0.8}deg`, opacity: 0.35 * enter}}
				viewBox="-540 -350 1080 700"
			>
				{Array.from({length: 14}, (_, i) => {
					const a = (i / 14) * Math.PI * 2;
					const b = a + Math.PI / 20;
					return (
						<polygon
							key={i}
							points={`0,0 ${900 * Math.cos(a)},${900 * Math.sin(a)} ${900 * Math.cos(b)},${900 * Math.sin(b)}`}
							fill={brand.colors.primary}
						/>
					);
				})}
			</svg>
			{Array.from({length: 36}, (_, i) => {
				const x = random(`cx${i}`) * 1080;
				const fall = (frame / fps) * (380 + random(`cv${i}`) * 420);
				return (
					<div
						key={i}
						style={{
							position: 'absolute',
							left: x,
							top: main.y - 40 + fall,
							width: 16,
							height: 26,
							background: CONFETTI[i % CONFETTI.length],
							rotate: `${frame * (6 + random(`cr${i}`) * 10)}deg`,
							borderRadius: 4,
						}}
					/>
				);
			})}
			<div
				style={{
					position: 'absolute',
					left: 0,
					right: 0,
					top: cy - 90,
					display: 'flex',
					flexDirection: 'column',
					alignItems: 'center',
					scale: String(0.3 + 0.7 * enter),
				}}
			>
				<span style={{...outlined(brand.colors.primary, 22, brand.colors.ink), fontSize: 168}}>RANK UP!</span>
				<span
					style={{
						...outlined(brand.colors.paper, 0),
						fontSize: 42,
						background: brand.colors.highlight,
						border: `5px solid ${brand.colors.ink}`,
						borderRadius: 999,
						padding: '6px 26px 10px',
						marginTop: 8,
					}}
				>
					NEW RANK UNLOCKED
				</span>
			</div>
		</div>
	);
};
