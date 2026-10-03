SurvivorPhoneWidgets={}
local D=SurvivorPhoneWidgets
D.c={bg={0.025,0.035,0.052},card={0.060,0.082,0.112},raised={0.095,0.125,0.160},
    glass={0.030,0.115,0.125},soft={0.070,0.160,0.165},line={0.18,0.25,0.30},
    text={0.93,0.96,0.98},muted={0.60,0.68,0.76},mint={0.40,0.94,0.72},
    purple={0.72,0.60,1.00},amber={1,0.72,0.34},red={1.00,0.32,0.38},blue={0.36,0.72,1.00}}
function D.fontHeight(font) return getTextManager():getFontHeight(font or UIFont.Small) end
function D.measure(text,font) return getTextManager():MeasureStringX(font or UIFont.Small,tostring(text)) end
function D.rect(p,x,y,w,h,color,alpha)
    if w>0 and h>0 then p:drawRect(x,y,w,h,(alpha or 1)*(p.opacity or 1),color[1],color[2],color[3]) end
end
function D.round(p,x,y,w,h,color,alpha,r)
    r=math.min(r or 9,math.floor(w/2),math.floor(h/2))
    D.rect(p,x,y+r,w,h-2*r,color,alpha)
    for i=0,r-1 do
        local inset=math.ceil(r-math.sqrt(r*r-(r-i-0.5)^2))
        D.rect(p,x+inset,y+i,w-2*inset,1,color,alpha)
        D.rect(p,x+inset,y+h-i-1,w-2*inset,1,color,alpha)
    end
end
function D.text(p,text,x,y,color,font,width)
    text=tostring(text or '');font=font or UIFont.Small;color=color or D.c.text
    -- Avoid half-visible warning lines where the content meets the fixed footer.
    if p.inBody and (y<p.bodyY or y+D.fontHeight(font)>p.bodyY+p.bodyH) then return end
    if width then
        local original=text
        while #text>0 and D.measure(text,font)>width do text=text:sub(1,-2) end
        if text~=original then
            while #text>0 and D.measure(text..'...',font)>width do text=text:sub(1,-2) end
            text=text..'...'
        end
    end
    p:drawText(text,x,y,color[1],color[2],color[3],1,font)
end
function D.wrap(p,text,x,y,width,color,font)
    font=font or UIFont.Small;local lh=D.fontHeight(font)+4;local line='';local start=y
    for word in tostring(text or ''):gmatch('%S+') do
        local proposed=line=='' and word or line..' '..word
        if line~='' and D.measure(proposed,font)>width then if p then D.text(p,line,x,y,color,font,width) end;y=y+lh;line=word else line=proposed end
    end
    if line~='' then if p then D.text(p,line,x,y,color,font,width) end;y=y+lh end
    return y-start
end
function D.icon(p,kind,x,y,color)
    local function r(a,b,w,h) D.rect(p,x+a,y+b,w,h,color) end
    if kind=='home' then r(1,1,8,8);r(13,1,8,8);r(1,13,8,8);r(13,13,8,8)
    elseif kind=='planner' then r(1,3,20,2);r(1,20,20,2);r(1,4,2,16);r(19,4,2,16);r(6,0,2,7);r(14,0,2,7);r(6,10,4,3);r(13,10,4,3);r(6,15,4,3)
    elseif kind=='skills' then r(2,13,4,9);r(9,7,4,15);r(16,1,4,21)
    elseif kind=='settings' then r(1,5,21,2);r(1,15,21,2);r(6,2,4,8);r(14,12,4,8)
    elseif kind=='check' then r(2,11,3,6);r(5,14,3,6);r(8,11,3,6);r(11,8,3,6);r(14,5,3,6)
    elseif kind=='store' then r(2,7,18,14);r(6,2,10,2);r(6,3,2,6);r(14,3,2,6)
    end
end
return D
