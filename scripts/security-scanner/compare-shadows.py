#!/usr/bin/env python3
"""compare-shadows.py — Compare Claude vs Gemini vs Codex security scanner results.

Reads logs/shadow-comparison.jsonl and Claude's own state to produce a side-by-side
quality comparison.

Usage:
  python compare-shadows.py [--days 7] [--format markdown|json]
"""

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


def load_jsonl(path, cutoff):
    entries = []
    if not path.exists():
        return entries
    with open(path) as f:
        for line in f:
            try:
                e = json.loads(line.strip())
                ts = e.get('timestamp', '')
                if ts >= cutoff:
                    entries.append(e)
            except (json.JSONDecodeError, KeyError):
                continue
    return entries


def load_claude_results(logs_dir, cutoff_date):
    """Parse Claude scanner logs for comparison."""
    results = []
    for log_file in sorted(logs_dir.glob('scan-*.log')):
        name = log_file.stem  # scan-2026-05-15
        try:
            file_date = name.replace('scan-', '')
            if file_date < cutoff_date:
                continue
        except ValueError:
            continue

        try:
            with open(log_file) as f:
                content = f.read()
            # Extract result from stream-json
            for line in content.split('\n'):
                if '"type":"result"' in line:
                    data = json.loads(line.strip())
                    result_text = data.get('result', '')
                    cost = data.get('total_cost_usd', 0)

                    critical = result_text.count('SEVERITY: critical')
                    high = result_text.count('SEVERITY: high')
                    medium = result_text.count('SEVERITY: medium')
                    low = result_text.count('SEVERITY: low')

                    results.append({
                        'agent': 'claude',
                        'component': 'security-scanner',
                        'timestamp': f'{file_date}T05:00:00Z',
                        'exit_code': 0,
                        'critical': critical,
                        'high': high,
                        'medium': medium,
                        'low': low,
                        'total_findings': critical + high + medium + low,
                        'cost': cost,
                        'result_preview': result_text[:1000],
                    })
                    break
        except (json.JSONDecodeError, OSError):
            continue
    return results


def analyze(entries):
    by_agent = defaultdict(list)
    for e in entries:
        by_agent[e.get('agent', 'unknown')].append(e)

    stats = {}
    for agent, runs in by_agent.items():
        successful = [r for r in runs if r.get('exit_code', 1) == 0]
        durations = [r.get('duration_s', 0) for r in successful if r.get('duration_s', 0) > 0]

        total_critical = sum(r.get('critical', 0) for r in successful)
        total_high = sum(r.get('high', 0) for r in successful)
        total_medium = sum(r.get('medium', 0) for r in successful)
        total_low = sum(r.get('low', 0) for r in successful)
        total_findings = sum(r.get('total_findings', 0) for r in successful)

        stats[agent] = {
            'total_runs': len(runs),
            'successful_runs': len(successful),
            'success_rate': f'{len(successful)/len(runs)*100:.0f}%' if runs else 'N/A',
            'avg_duration_s': f'{sum(durations)/len(durations):.0f}' if durations else 'N/A',
            'total_critical': total_critical,
            'total_high': total_high,
            'total_medium': total_medium,
            'total_low': total_low,
            'total_findings': total_findings,
            'avg_findings': f'{total_findings/len(successful):.1f}' if successful else '0',
        }

    return stats


def format_markdown(stats, days):
    lines = [f'# Security Scanner Shadow Comparison (last {days} days)\n']

    if not stats:
        lines.append('No comparison data found.\n')
        return '\n'.join(lines)

    agents = sorted(stats.keys())
    lines.append('| Metric | ' + ' | '.join(agents) + ' |')
    lines.append('|---|' + '---|' * len(agents))

    metrics = [
        ('Total runs', 'total_runs'),
        ('Success rate', 'success_rate'),
        ('Avg duration (s)', 'avg_duration_s'),
        ('Total findings', 'total_findings'),
        ('Avg findings/run', 'avg_findings'),
        ('Critical', 'total_critical'),
        ('High', 'total_high'),
        ('Medium', 'total_medium'),
        ('Low', 'total_low'),
    ]
    for label, key in metrics:
        vals = ' | '.join(str(stats[a].get(key, 'N/A')) for a in agents)
        lines.append(f'| {label} | {vals} |')

    lines.append('\n## Key Question: Can Gemini/Codex Replace Claude Here?')
    lines.append('Compare finding counts: shadows should catch the same critical/high issues.')
    lines.append('If a shadow misses findings Claude catches, it is not ready for handoff.')

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--days', type=int, default=7)
    parser.add_argument('--format', choices=['markdown', 'json'], default='markdown')
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    comparison_log = script_dir / 'logs' / 'shadow-comparison.jsonl'
    claude_logs_dir = script_dir / 'logs'

    cutoff = (datetime.now(timezone.utc) - timedelta(days=args.days)).strftime('%Y-%m-%dT%H:%M:%SZ')
    cutoff_date = (datetime.now(timezone.utc) - timedelta(days=args.days)).strftime('%Y-%m-%d')

    # Load shadow results
    entries = load_jsonl(comparison_log, cutoff)

    # Load Claude results from its own logs
    claude_results = load_claude_results(claude_logs_dir, cutoff_date)
    entries.extend(claude_results)

    if not entries:
        print(f'No comparison data found yet.')
        print('Shadow runners need to accumulate data first.')
        sys.exit(0)

    stats = analyze(entries)

    if args.format == 'json':
        print(json.dumps(stats, indent=2))
    else:
        print(format_markdown(stats, args.days))


if __name__ == '__main__':
    main()
