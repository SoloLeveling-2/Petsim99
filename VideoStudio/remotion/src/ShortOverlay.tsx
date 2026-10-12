import React from 'react';
import {AbsoluteFill, Sequence, useVideoConfig} from 'remotion';
import {DisclosureBadge, DisclosureCard} from './components/Disclosure';
import {Hook} from './components/Hook';
import {Outro} from './components/Outro';
import {InsetFrame, PanelHighlight, QuestPop} from './components/QuestPop';
import {RankUp} from './components/RankUp';
import {RunClock} from './components/RunClock';
import {StarCounter} from './components/StarCounter';
import {sec} from './theme';
import {OverlayProps} from './types';

const POP_S = 1.9;
const RANK_UP_S = 2.4;

// Transparent overlay only: the gameplay underneath is composited by FFmpeg.
export const ShortOverlay: React.FC<OverlayProps> = ({overlay, layout, brand, duration}) => {
	const {fps} = useVideoConfig();
	const main = layout.main_rect;
	const total = sec(duration, fps);
	const span = (start: number, end: number) => ({
		from: sec(start, fps),
		durationInFrames: Math.max(1, sec(end, fps) - sec(start, fps)),
	});
	const counterStart = overlay.counter.length ? overlay.counter[0].t : null;
	const clockStart = overlay.clock.length ? overlay.clock[0].t : null;

	return (
		<AbsoluteFill style={{backgroundColor: 'transparent'}}>
			{layout.panel_rect ? (
				<Sequence {...span(overlay.hook.end, duration)} premountFor={fps}>
					<InsetFrame rect={layout.panel_rect} label="LIVE QUEST PANEL" brand={brand} />
				</Sequence>
			) : null}
			{layout.star_rect ? (
				<Sequence {...span(overlay.hook.end, overlay.outro.start)} premountFor={fps}>
					<InsetFrame rect={layout.star_rect} label="IN-GAME" brand={brand} />
				</Sequence>
			) : null}

			{overlay.quests.map((pop, i) =>
				layout.panel_rect && pop.status === 'confirmed' ? (
					<Sequence key={`ph${i}`} {...span(pop.t, pop.t + 1.5)} premountFor={fps}>
						<PanelHighlight rect={layout.panel_rect} brand={brand} />
					</Sequence>
				) : null,
			)}

			{counterStart !== null ? (
				<Sequence {...span(counterStart, overlay.outro.start + 0.3)} premountFor={fps}>
					<StarCounter
						keys={overlay.counter}
						start={counterStart}
						end={overlay.outro.start + 0.3}
						main={main}
						brand={brand}
					/>
				</Sequence>
			) : null}
			{clockStart !== null ? (
				<Sequence {...span(clockStart, overlay.outro.start)} premountFor={fps}>
					<RunClock keys={overlay.clock} speedups={overlay.speedups} start={clockStart} main={main} brand={brand} />
				</Sequence>
			) : null}

			{overlay.rank_ups.map((r, i) => (
				<Sequence key={`ru${i}`} {...span(r.t, r.t + RANK_UP_S)} premountFor={fps}>
					<RankUp durationInFrames={sec(RANK_UP_S, fps)} main={main} brand={brand} />
				</Sequence>
			))}
			{overlay.quests.map((pop, i) => (
				<Sequence key={`qp${i}`} {...span(pop.t, pop.t + POP_S)} premountFor={fps}>
					<QuestPop pop={pop} durationInFrames={sec(POP_S, fps)} main={main} brand={brand} />
				</Sequence>
			))}

			<Sequence {...span(overlay.outro.start, duration)} premountFor={fps}>
				<Outro outro={overlay.outro} main={main} brand={brand} />
			</Sequence>
			<Sequence {...span(overlay.hook.start, overlay.hook.end)} premountFor={fps}>
				<Hook
					text={overlay.hook.text}
					sub={overlay.hook.sub}
					durationInFrames={sec(overlay.hook.end - overlay.hook.start, fps)}
					brand={brand}
				/>
			</Sequence>
			<Sequence {...span(overlay.disclosure.card_start, overlay.disclosure.card_end)} premountFor={fps}>
				<DisclosureCard
					title={overlay.disclosure.title}
					body={overlay.disclosure.body}
					durationInFrames={sec(overlay.disclosure.card_end - overlay.disclosure.card_start, fps)}
					brand={brand}
				/>
			</Sequence>
			<Sequence
				from={sec(overlay.disclosure.badge_start, fps)}
				durationInFrames={Math.max(1, total - sec(overlay.disclosure.badge_start, fps))}
				premountFor={fps}
			>
				<DisclosureBadge text={overlay.disclosure.text} brand={brand} />
			</Sequence>
		</AbsoluteFill>
	);
};
