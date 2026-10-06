"""Redraw paper figures from frozen plotting inputs; no packet processing."""

from pathlib import Path
import argparse
import csv
import json

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import numpy as np

ROOT = Path(__file__).resolve().parent
COLORS = ['lightcoral', 'cornflowerblue', 'mediumseagreen']


def normalize(x):
    x = np.asarray(x, dtype=float)
    return (x - x.min()) / max(np.ptp(x), np.finfo(float).eps)


def save(fig, output, name):
    fig.savefig(output / (name + '.png'), dpi=180, bbox_inches='tight')
    plt.close(fig)
    print(name)


def boxplot(values, labels, ylabel):
    fig, ax = plt.subplots(figsize=(5.4, 3.1), layout='constrained')
    boxes = ax.boxplot(values, patch_artist=True,
                       widths=.5, showfliers=False)
    ax.set_xticks(np.arange(1, len(labels)+1), labels)
    for i, patch in enumerate(boxes['boxes']):
        patch.set(facecolor=COLORS[i % 3], alpha=.55)
    ax.set_ylabel(ylabel)
    ax.grid(axis='y', ls='--', alpha=.35)
    return fig, ax


def bars(labels, values, ylabel, xlabel, ylim=None):
    fig, ax = plt.subplots(figsize=(5.4, 3.1), layout='constrained')
    x = np.arange(len(values))
    ax.bar(x, values, color='cornflowerblue', edgecolor='black', width=.6)
    ax.set(xticks=x, xticklabels=labels, ylabel=ylabel, xlabel=xlabel)
    if ylim: ax.set_ylim(*ylim)
    top = ax.get_ylim()[1]
    for i, value in enumerate(values):
        ax.text(i, value + .02*top, f'{value:.3g}', ha='center', va='bottom', fontsize=9)
    ax.grid(axis='y', ls='--', alpha=.35)
    ax.set_axisbelow(True)
    return fig


def confusion(values):
    fig, ax = plt.subplots(figsize=(4.1, 3.5), layout='constrained')
    cmap = LinearSegmentedColormap.from_list('paper',
        [(0,'white'),(.15,'red'),(1,'cornflowerblue')])
    ax.imshow(values, vmin=0, vmax=100, cmap=cmap)
    ax.set(xticks=range(4), yticks=range(4), xticklabels=['Ap','Se','St','Ex'],
           yticklabels=['Ap','Se','St','Ex'], xlabel='Predicted interaction',
           ylabel='True interaction')
    for i,j in np.ndindex(values.shape):
        if values[i,j] > 0:
            ax.text(j,i,f'{values[i,j]:g}%',ha='center',va='center',fontsize=10)
    return fig


def reproduce(output):
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({'font.size':11, 'svg.fonttype':'none', 'axes.spines.top':False,
                         'axes.spines.right':False})
    metrics = []
    def record(name, labels, values):
        metrics.extend((name, str(label), float(value)) for label,value in zip(labels,values))

    with np.load(ROOT/'paper'/'figure_data.npz', allow_pickle=False) as data:
        # Environment mapping is taken directly from 1_tracking_error_v2.py.
        labels = ['Lab Room','Lecture Room','Meeting Room']
        envs = [data[k] for k in ['env3','env2','env1']]
        fig, ax = boxplot(envs,labels,'Angle error (deg)')
        ax.set_xlabel('Environment')
        save(fig,output,'fig08_tracking_error_boxplot')
        fig, ax = plt.subplots(figsize=(5.4,3.1),layout='constrained')
        for x,label,color,style in zip(envs,labels,COLORS,[':','-','--']):
            ax.plot(np.sort(x),np.arange(1,len(x)+1)/len(x),label=label,color=color,ls=style,lw=2)
        ax.set(xlabel='Angle error (deg)',ylabel='CDF',ylim=(0,1),xlim=(0,max(map(np.max,envs))))
        ax.grid(ls='--',alpha=.35); ax.legend(loc='lower right',frameon=False)
        save(fig,output,'fig09_tracking_error_cdf')
        record('tracking_median_error_degrees',labels,list(map(np.median,envs)))

        save(bars(data['side_labels'],data['side_values'],'Accuracy (%)',
                  'Angle difference (deg)',(0,108)),output,'fig11_side_accuracy')
        for key,num in [('los',12),('wall',13)]:
            cm=data[key+'_cm']
            if not np.allclose(cm.sum(axis=1),100): raise ValueError('Invalid confusion percentages')
            save(confusion(cm),output,f'fig{num}_interaction_{key}')
            record(key+'_class_accuracy_percent',['Approach','Separation','Static','Exchange'],np.diag(cm))

        # Literal waveform samples from 3_waveform_res.py. Preserve their timing.
        t = data['wave_x'] - data['wave_x'][0]
        keep = t <= 30
        t = t[keep]
        waves = [normalize(data['wave_'+k][keep]) for k in ['gt','bfmrow_phi','bfmr_phi','ours']]
        names = ['Ground truth','Raw BFM','BFM ratio','BFMScan']
        fig, axes = plt.subplots(4,1,sharex=True,figsize=(8,4.5),layout='constrained')
        for ax, wave, name, color in zip(axes,waves,names,['black','mediumseagreen','lightcoral','cornflowerblue']):
            ax.plot(t,wave,color=color,lw=1.7,label=name)
            ax.set_yticks([]); ax.legend(loc='center left',bbox_to_anchor=(1, .5),frameon=False,fontsize=9)
            ax.grid(ls='--',alpha=.25)
        axes[-1].set(xlabel='Time (s)',xlim=(0,30))
        fig.supylabel('Normalized respiration amplitude')
        save(fig,output,'fig14_respiration_waveforms')
        fig, ax = plt.subplots(figsize=(8,3.2),layout='constrained')
        ax.plot(t,waves[0],'k-',label='Ground truth',lw=1.6)
        ax.plot(t,waves[-1],color='cornflowerblue',label='BFMScan',lw=1.6)
        ax.set(xlabel='Time (s)',ylabel='Normalized amplitude',xlim=(0,30))
        ax.legend(frameon=False); ax.grid(ls='--',alpha=.3)
        save(fig,output,'fig14_gt_estimate_overlay')

        # Match the original figure's min-max normalization and 10-sample windows.
        # These are sample windows on irregular timestamps, not ten-second windows.
        similarities=[]
        for w in waves[1:]:
            values=[]
            for i in range(len(t)-10+1):
                a,b=w[i:i+10],waves[0][i:i+10]
                values.append(np.dot(a,b)/max(np.linalg.norm(a)*np.linalg.norm(b),np.finfo(float).eps))
            similarities.append(np.asarray(values))
        fig, _ = boxplot(similarities,names[1:],'Cosine similarity')
        save(fig,output,'fig15_waveform_similarity')
        record('waveform_median_cosine',names[1:],list(map(np.median,similarities)))

        block = [np.median(data[f'blockage_{i}']) for i in range(2)]
        save(bars(data['blockage_labels'],block,'Cosine similarity','Blockage type',(0,1.07)),
             output,'fig16_body_blockage')
        inter = [np.median(data[f'interference_{i}']) for i in range(3)]
        save(bars(data['interference_labels'],inter,'MAE (bpm)','Interference type',(0,1)),
             output,'fig17_interference')
        record('interference_median_mae_bpm',data['interference_labels'],inter)
        users = [data[f'users_{i}'] for i in range(3)]
        fig, ax = boxplot(users,['1','2','3'],'MAE (bpm)')
        ax.set_xlabel('Number of users'); save(fig,output,'fig18_multiuser_respiration')
        record('multiuser_median_mae_bpm',[1,2,3],list(map(np.median,users)))
        save(bars(data['static_labels'],data['static_values'],'Mean angle error (deg)',
                  'Angle (deg)',(0,21)),output,'fig20_static_angle_error')
        csi=[np.median(data[f'csi_{i}']) for i in range(2)]
        save(bars(data['csi_labels'],csi,'Median angle error (deg)','Channel representation',(0,7)),
             output,'fig21_csi_bfm')

        # Additional views of unchanged saved spectra. Packet indices are kept;
        # these views do not assert the layout/time calibration of Figures 7/10.
        for prefix,name in [('tracking_spectrum','tracking')]+[
                ('aoa_spectrum_'+p,n) for p,n in zip(['close','far','par','switch'],
                ['approach','separation','static','exchange'])]:
            x=data[prefix+'_X']; a=data[prefix+'_angle_grid'].ravel()
            packets=data[prefix+'_packets_to_show'].ravel()
            fig,ax=plt.subplots(figsize=(6,3.4),layout='constrained')
            ax.pcolormesh(packets,a,x.T,cmap='jet',shading='nearest')
            ax.set(xlabel='Packet index',ylabel='Stored angle coordinate (deg)',title=name.capitalize())
            save(fig,output,'spectrum_'+name)
        # Source fingerprints travel with the numeric input archive.
        assert len(json.loads(str(data['source_sha256_json']))) >= 10
    with (output/'summary.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.writer(f); writer.writerow(['metric','condition','value']); writer.writerows(metrics)
    print(f'Wrote figures and summary to {output}')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',type=Path,default=ROOT/'results'/'paper')
    reproduce(parser.parse_args().output_dir)
