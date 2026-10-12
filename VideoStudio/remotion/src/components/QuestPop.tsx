import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {dropShadow, outlined} from '../theme';
import {Brand, QuestPopData, Rect} from '../types';
import {CheckIcon, StarIcon} from './Icons';

// "QUEST COMPLETE" callout over the gameplay at the moment the completion is visible.
export const QuestPop: React.FC<{pop: QuestPopData; durationInFrames: number; main: Rect; brand: Brand}> = ({
	pop,
	durationInFrames,
	main,
	brand,
}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const enter = spring({frame, fps, config: {damping: 9, stiffness: 200}});
	const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	const confirmed = pop.status === 'confirmed';
	const color = confirmed ? brand.colors.accent : brand.colors.highlight;
	return (
		<div
			style={{
				position: 'absolute',
				left: 0,
				right: 0,
				top: main.y + main.h * 0.42,
				display: 'flex',
				flexDirection: 'column',
				alignItems: 'center',
				gap: 14,
				opacity: exit,
				translate: `0 ${(1 - exit) * -50}px`,
				filter: dropShadow,
			}}
		>
			<div
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: 16,
					background: color,
					border: `6px solid ${brand.colors.ink}`,
					borderRadius: 26,
					padding: '14px 30px 16px 18px',
					scale: String(0.5 + 0.5 * enter),
					rotate: `${(1 - enter) * -6}deg`,
				}}
			>
				{confirmed ? <CheckIcon size={70} /> : <StarIcon size={70} fill={brand.colors.primary} />}
				<span style={{...outlined(brand.colors.paper, 12, brand.colors.ink), fontSize: 72}}>{pop.label}</span>
			</div>
			<div
				style={{
					display: 'flex',
					alignItems: 'center',
					gap: 18,
					opacity: spring({frame: frame - 5, fps, config: {damping: 14}}),
				}}
			>
				{pop.name ? (
					<span style={{...outlined(brand.colors.paper, 10, brand.colors.ink), fontSize: 50}}>{pop.name}</span>
				) : null}
				<span
					style={{
						display: 'flex',
						alignItems: 'center',
						gap: 6,
						background: 'rgba(20,18,31,0.85)',
						border: `4px solid ${brand.colors.primary}`,
						borderRadius: 999,
						padding: '4px 18px 4px 8px',
					}}
				>
					<StarIcon size={46} fill={brand.colors.primary} />
					<span style={{...outlined(brand.colors.primary, 0), fontSize: 46}}>+{pop.stars}</span>
				</span>
			</div>
		</div>
	);
};

// Pulsing outline around the live quest-panel inset when a quest completes.
export const PanelHighlight: React.FC<{rect: Rect; brand: Brand}> = ({rect, brand}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const t = frame / fps;
	const pulse = 0.5 + 0.5 * Math.cos(t * Math.PI * 3.3);
	const fade = interpolate(t, [0, 0.1, 1.2, 1.5], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<div
			style={{
				position: 'absolute',
				left: rect.x - 12,
				top: rect.y - 12,
				width: rect.w + 24,
				height: rect.h + 24,
				border: `10px solid ${brand.colors.accent}`,
				borderRadius: 22,
				boxShadow: `0 0 ${30 + 30 * pulse}px ${brand.colors.accent}`,
				opacity: fade * (0.55 + 0.45 * pulse),
			}}
		/>
	);
};

// Static frames that label the real in-game insets.
export const InsetFrame: React.FC<{rect: Rect; label: string; brand: Brand}> = ({rect, label, brand}) => (
	<>
		<div
			style={{
				position: 'absolute',
				left: rect.x - 6,
				top: rect.y - 6,
				width: rect.w + 12,
				height: rect.h + 12,
				border: `6px solid ${brand.colors.paper}`,
				borderRadius: 16,
				boxShadow: '0 6px 0 rgba(0,0,0,0.35)',
			}}
		/>
		<div
			style={{
				...outlined(brand.colors.ink, 0),
				position: 'absolute',
				left: rect.x + 14,
				top: rect.y - 24,
				fontSize: 24,
				background: brand.colors.paper,
				borderRadius: 10,
				padding: '3px 12px 5px',
			}}
		>
			{label}
		</div>
	</>
);
