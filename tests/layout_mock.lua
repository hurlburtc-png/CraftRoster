-- Resolve WoW anchor constraints for layout checks; this does not render fonts/templates.
local originalCreate = CreateFrame
local function fraction(point, axis)
 if axis == 'x' then
  if point:find('LEFT') then return 0 elseif point:find('RIGHT') then return 1 end
 else
  if point:find('BOTTOM') then return 0 elseif point:find('TOP') then return 1 end
 end
 return 0.5
end
local axisBounds
axisBounds = function(frame, axis)
 local sizeKey = axis=='x' and 'width' or 'height'
 if frame==UIParent then return 0, rawget(frame,sizeKey) or (axis=='x' and 1920 or 1080) end
 local constraints={}
 for _,p in pairs(rawget(frame,'anchors') or {}) do
  local origin,size=axisBounds(p.relative,axis)
  constraints[#constraints+1]={fraction(p.point,axis),origin+size*fraction(p.relativePoint,axis)+(axis=='x' and p.x or p.y)}
 end
 local size=rawget(frame,sizeKey) or 100
 for i=1,#constraints do
  for j=i+1,#constraints do
   local a,b=constraints[i],constraints[j]
   if a[1]~=b[1] then
    size=(b[2]-a[2])/(b[1]-a[1])
    return a[2]-a[1]*size,size
   end
  end
 end
 if constraints[1] then return constraints[1][2]-constraints[1][1]*size,size end
 return 0,size
end
local function instrument(frame)
 frame.anchors={}
 function frame:SetPoint(point,relative,relativePoint,x,y)
  if type(relative)=='number' or relative==nil then
   x,y=relative or 0,relativePoint or 0
   relative,relativePoint=self.parent or UIParent,point
  else
   relativePoint=relativePoint or point; x=x or 0; y=y or 0
  end
  self.anchors[point]={point=point,relative=relative,relativePoint=relativePoint,x=x,y=y}
 end
 function frame:ClearAllPoints() self.anchors={} end
 function frame:SetAllPoints(relative)
  self:ClearAllPoints(); self:SetPoint('TOPLEFT',relative or self.parent,'TOPLEFT',0,0)
  self:SetPoint('BOTTOMRIGHT',relative or self.parent,'BOTTOMRIGHT',0,0)
 end
 function frame:SetWidth(value) self.width=value end
 function frame:SetHeight(value) self.height=value end
 function frame:GetWidth() local _,size=axisBounds(self,'x'); return size end
 function frame:GetHeight() local _,size=axisBounds(self,'y'); return size end
 function frame:SetFrameStrata(value) self.strata=value end
 function frame:SetEnabled(value) self.enabled=value end
 function frame:SetChecked(value) self.checked=value end
 function frame:GetChecked() return self.checked end
 function frame:SetMaxLines(value) self.maxLines=value end
 function frame:SetClampedToScreen(value) self.clamped=value end
 function frame:SetResizeBounds(w,h) self.minWidth=w; self.minHeight=h end
 return frame
end
function CreateFrame(...) return instrument(originalCreate(...)) end
instrument(UIParent); UIParent:SetSize(1920,1080)
function bounds(frame)
 local x,w=axisBounds(frame,'x'); local y,h=axisBounds(frame,'y')
 return x,y,w,h
end
function inside(child,parent)
 local x,y,w,h=bounds(child); local px,py,pw,ph=bounds(parent)
 assert(w>0 and h>0,'Collapsed frame')
 assert(x>=px-0.1 and y>=py-0.1 and x+w<=px+pw+0.1 and y+h<=py+ph+0.1,'Frame outside parent')
end
function apart(a,b)
 local x,y,w,h=bounds(a); local bx,by,bw,bh=bounds(b)
 assert(x+w<=bx+0.1 or bx+bw<=x+0.1 or y+h<=by+0.1 or by+bh<=y+0.1,'Overlapping controls')
end
