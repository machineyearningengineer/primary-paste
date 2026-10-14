#!/usr/bin/env python3
"""Revise the existing Tesseract 0.3.1 document using real guest footage.

Import Footage/Demo.mp4 as safari-textedit-real, checkout the project, then:
    python3 author.py .tesseract-work/real-demo.json .tesseract-work/final.json
Commit the result with tsrct project commit. Source timing remains inspectable.
"""
import copy
import json
from pathlib import Path
import sys

W, H = 1280, 500
DURATION = 7400
SCALE = .9625
INK = [.09, .09, .10, 1]
MUTED = [.38, .38, .40, 1]
PAPER = [.965, .965, .973, 1]

def transform(x, y, anchor=(0, 0)):
    return dict(anchorPoint=list(anchor), position=[x,y], scale=[100,100], rotation=0, opacity=100)

def rect(identifier, name, x, y, w, h, color, start=0, duration=DURATION, radius=0):
    return dict(type="Rect", id=identifier, name=name, blendMode="normal", activeRange=dict(start=start,duration=duration),
                transform=transform(x,y),rect=dict(size=[w,h],fillEnabled=True,fillColor=color,roundness=radius))

def label(original, name, words, x, y, size, width, start=0, duration=DURATION, color=INK, style="Medium"):
    layer=copy.deepcopy(original)
    layer.update(name=name,isHidden=False,activeRange=dict(start=start,duration=duration),transform=transform(x,y))
    layer["sourceText"].update(text=words,fontSize=size,fontStyle=style,fillColor=color,boxSize=[width,40])
    return layer

def clip(identifier, name, source_start, edit_start, duration):
    return dict(type="Video",id=identifier,name=name,blendMode="normal",
                playback=dict(type="windowed",inputRange=dict(start=edit_start,duration=duration),
                              mapping=dict(type="linear",input=dict(start=edit_start,duration=duration),
                                           output=dict(start=source_start,duration=duration)),inputOffsetMs=0),
                sourceRange=dict(start=source_start,duration=duration),sourceIntrinsicDuration=18033,
                transform=dict(anchorPoint=[0,0],position=[24,64],scale=[96.25,96.25],rotation=0,opacity=100),
                source=dict(assetId="safari-textedit-real",fit="contain"))

def animator(identifier, prop, code):
    return dict(target=dict(kind="layer",layerId=identifier,propertyType=prop),
                animator=dict(type="jsScript",layerTimeJsCode=code))

def revise(document):
    by_id={layer["id"]:layer for layer in document["composition"]["layers"]}
    document["dimensions"]=dict(width=W,height=H)
    document["duration"]=DURATION/1000
    document["composition"]["name"]="Safari to TextEdit"
    # Reuse original typography identities; replace the obsolete illustrated windows.
    top=label(by_id[3],"Product","Primary Paste",24,20,26,450)
    steps=[
        label(by_id[36],"Select","1  Select text",885,23,24,365,start=0,duration=2200,color=MUTED),
        label(by_id[37],"Middle-click","2  Middle-click",885,23,24,365,start=2200,duration=2850,color=MUTED),
        label(by_id[38],"Pasted","3  Pasted",885,23,24,365,start=5050,duration=2350,color=MUTED),
    ]
    footer=label(by_id[6],"Clipboard kept","Your normal clipboard stays separate.",24,457,23,800,color=MUTED,style="Regular")
    apps=label(by_id[4],"Apps","Safari → TextEdit",1030,460,18,245,color=MUTED,style="Regular")
    halo=rect(1003,"Cursor highlight",0,0,40,40,[.04,.39,.9,.12],radius=20)
    halo["transform"]["anchorPoint"]=[20,20]
    halo["rect"].update(strokeEnabled=True,strokeColor=[.04,.39,.9,.4],strokeWidth=1.5)
    ring=rect(1004,"Middle-click pulse",24+654*SCALE,64+(202-24)*SCALE,40,40,[0,0,0,0],start=4450,duration=600,radius=20)
    ring["transform"]["anchorPoint"]=[20,20]
    ring["rect"].update(fillEnabled=False,strokeEnabled=True,strokeColor=[.04,.39,.9,.8],strokeWidth=2)
    background=copy.deepcopy(by_id[1]);background.update(name="Canvas",isHidden=False,activeRange=dict(start=0,duration=DURATION))
    background["rect"].update(size=[W,H],fillColor=PAPER)
    document["composition"]["layers"]=[top,*steps,footer,apps,rect(1005,"Footer",0,440,W,60,PAPER),ring,halo,
        clip(1000,"Select: source 2.85–4.65 s",2850,0,1800),
        clip(1001,"Cursor travel: source 6.35–8.65 s",6350,1800,2300),
        clip(1002,"Paste and result: source 10.35–13.65 s",10350,4100,3300),background]
    retained={layer["id"] for layer in document["composition"]["layers"]}
    entries=document["composition"].setdefault("dynamics",{}).setdefault("entries",[])
    entries[:]=[entry for entry in entries if entry.get("target",{}).get("layerId") in retained]
    entries[:]=[entry for entry in entries if entry.get("target",{}).get("layerId") not in [1003,1004]]
    x="const t=input.time.seconds; const x=t<.4?43:t<.8?43+200*(t-.4)/.4:t<2.317?243:t<3.667?243+411*Math.max(0,Math.min(9,Math.floor((t-2.317)/.15)))/9:654; return 24+x*.9625;"
    y="const t=input.time.seconds; const y=t<2.317?300:t<3.667?300-98*Math.max(0,Math.min(9,Math.floor((t-2.317)/.15)))/9:202; return 64+(y-24)*.9625;"
    entries.extend([animator(1003,"positionX",x),animator(1003,"positionY",y),
        animator(1003,"opacity","return 100*Math.max(0,Math.min(1,(5.65-input.time.seconds)/.6));"),
        animator(1004,"scaleX","return 100+120*Math.min(1,input.time.seconds/.6);"),
        animator(1004,"scaleY","return 100+120*Math.min(1,input.time.seconds/.6);"),
        animator(1004,"opacity","return 100*Math.max(0,1-input.time.seconds/.6);")])
    return document

if __name__=="__main__":
    if len(sys.argv)!=3:sys.exit("Usage: author.py checkout.json output.json")
    Path(sys.argv[2]).write_text(json.dumps(revise(json.loads(Path(sys.argv[1]).read_text())),indent=2)+"\n")
