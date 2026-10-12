import React from 'react';
import {Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {clamp01, outlined} from '../theme';
import {Brand, Overlay, Rect} from '../types';
import {StarIcon} from './Icons';

export const Outro: React.FC<{outro: Overlay['outro']; main: Rect; brand: Brand}> = ({outro, main, brand}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const t = frame / fps;
	const dim = interpolate(t, [0, 0.35], [0, 0.6], {extrapolateRight: 'clamp'});
	const card = spring({frame: frame - 3, fps, config: {damping: 12, stiffness: 150}});
	const counted = outro.total === null ? null : Math.round(outro.total * Easing.out(Easing.cubic)(clamp01(t / 1.0)));
	const facts = [
		outro.quests ? `${outro.quests} QUEST${outro.quests === 1 ? '' : 'S'}` : null,
		outro.rank_ups ? `${outro.rank_ups} RANK UP${outro.rank_ups === 1 ? '' : 'S'}` : null,
		`${outro.minutes} MIN RECORDING`,
	].filter(Boolean);
	return (
		<>
			<div
				style={{
					position: 'absolute',
					left: main.x,
					top: main.y,
					width: main.w,
					height: main.h,
					background: `rgba(20,18,31,${dim})`,
				}}
			/>
			<div
				style={{
					position: 'absolute',
					left: 70,
					right: 70,
					top: main.y + main.h * 0.16,
					display: 'flex',
					flexDirection: 'column',
					alignItems: 'center',
					gap: 22,
					scale: String(0.6 + 0.4 * card),
					opacity: card,
				}}
			>
				<span style={{...outlined(brand.colors.paper, 10, brand.colors.ink), fontSize: 56}}>
					{counted === null ? 'AUTO RANKING RUN' : 'WHOLE RUN TOTAL'}
				</span>
				{counted !== null ? (
					<div style={{display: 'flex', alignItems: 'center', gap: 18}}>
						<StarIcon size={150} fill={brand.colors.primary} />
						<span style={{...outlined(brand.colors.primary, 20, brand.colors.ink), fontSize: 190}}>+{counted}</span>
					</div>
				) : null}
				<span style={{...outlined(brand.colors.paper, 8, brand.colors.ink), fontSize: 42, textAlign: 'center'}}>
					{facts.join('  •  ')}
				</span>
				<span
					style={{
						...outlined(brand.colors.ink, 0),
						fontSize: 48,
						background: brand.colors.accent,
						border: `6px solid ${brand.colors.ink}`,
						borderRadius: 999,
						padding: '10px 36px 14px',
						marginTop: 14,
					}}
				>
					{outro.cta}
				</span>
				<span style={{...outlined(brand.colors.paper, 6, brand.colors.ink), fontSize: 36}}>{outro.handle}</span>
			</div>
		</>
	);
};
