'use client'

import type { ReactNode } from 'react'
import { Bar, BarChart, Cell } from 'recharts'

import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { type ChartConfig, ChartContainer } from '@/components/ui/chart'

// Types

export type HealthMetric = {
  label: string
  detail: string
  percentage: number
}

export type ServiceHealthCardProps = {
  title?: ReactNode
  description?: ReactNode
  action?: ReactNode
  metrics: HealthMetric[]
  className?: string
}

// Constants

const TOTAL_BARS = 10

// Helpers

function makeBarData(percentage: number) {
  const filled = Math.round((percentage * TOTAL_BARS) / 100)

  return Array.from({ length: TOTAL_BARS }, (_, i) => ({ v: i < filled ? 1 : 0.001 }))
}

function barColor(percentage: number): string {
  if (percentage < 40) return 'var(--chart-1)' // red — critical
  if (percentage < 75) return 'var(--chart-4)' // Yellow — warning

  return 'var(--chart-2)' // green  — healthy
}

const chartConfig = { v: { label: 'Value' } } satisfies ChartConfig

// Bar Chart

const MetricRow = ({ label, detail, percentage }: HealthMetric) => {
  const data = makeBarData(percentage)
  const color = barColor(percentage)

  return (
    <div className='flex flex-col gap-2'>
      <p className='text-muted-foreground text-sm font-medium'>{label}</p>
      <div className='flex items-center gap-4'>
        <ChartContainer config={chartConfig} className='h-9 w-20'>
          <BarChart data={data} margin={{ left: 0, right: 0 }} maxBarSize={16} accessibilityLayer>
            <Bar
              dataKey='v'
              radius={12}
              background={{
                fill: 'color-mix(in oklab, var(--primary) 10%, transparent)',
                radius: 12
              }}
            >
              {data.map((entry, i) => (
                <Cell key={i} fill={entry.v > 0 ? color : 'transparent'} />
              ))}
            </Bar>
          </BarChart>
        </ChartContainer>
        <div>
          <p className='text-base font-semibold'>{percentage}%</p>
          <p className='text-muted-foreground text-sm whitespace-nowrap'>{detail}</p>
        </div>
      </div>
    </div>
  )
}

const ServiceHealthCard = ({ title = 'Service Health', description, action, metrics, className }: ServiceHealthCardProps) => (
  <Card className={className}>
    <CardHeader className='grid-rows-none'>
      <CardTitle className='text-base font-semibold'>{title}</CardTitle>
      {description && <CardDescription>{description}</CardDescription>}
      {action && <CardAction>{action}</CardAction>}
    </CardHeader>
    <CardContent>
      <div className='grid gap-6 sm:grid-cols-3'>
        {metrics.map(metric => (
          <MetricRow key={metric.label} {...metric} />
        ))}
      </div>
    </CardContent>
  </Card>
)

export default ServiceHealthCard
