local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService") -- Tambahan TweenService untuk animasi
 
-- Disable default backpack
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
 
local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")
local gui = script.Parent

-- Memastikan ZIndexBehavior tidak menyebabkan tumpang tindih
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
 
-- UI References
local hotbarFrame = gui:WaitForChild("HotbarFrame")
local menuFrame = gui:WaitForChild("MenuFrame")
local scrollingFrame = menuFrame:WaitForChild("ScrollingFrame")
local slotTemplate = script:WaitForChild("Slot")
slotTemplate.Visible = false
 
-- Setup MenuButton
local menuButton = hotbarFrame:FindFirstChild("MenuButton")
 
-- Variables
local maxHotbarSlots = 6
local inventory = {}
local activeUIs = {}
local displaySlots = {}
local isMenuOpen = false
local equippedTool = nil
 
-- Drag System Variables
local isDragging = false
local dragUI = nil
local draggedToolData = nil
local dragConnection = nil
local currentInput = nil
local dragOffset = Vector2.zero
local lastDragPosition = Vector2.zero -- Untuk melacak posisi touch mobile yang akurat

-- Animasi Hover Variables
local originalSize = slotTemplate.Size
local hoverSize = UDim2.new(
    originalSize.X.Scale, originalSize.X.Offset * 1.5, -- Menambah 1/2 offset (1.5x)
    originalSize.Y.Scale, originalSize.Y.Offset * 1.5
)
local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
 
-- ==========================================
-- SETUP DISPLAY SLOTS (1-6)
-- ==========================================
for i = 1, maxHotbarSlots do
    local ds = slotTemplate:Clone()
    ds.Name = "DisplaySlot" .. i
    ds.LayoutOrder = i
    ds.BackgroundTransparency = 0.5
    ds.ToolIcon.Visible = false
    ds.ToolName.Visible = false
    ds.SlotNumber.Text = tostring(i)
    ds.SlotNumber.Visible = true
    ds.Visible = false
    ds.Parent = hotbarFrame
    displaySlots[i] = ds
end
 
-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================
local function getToolCount()
    local count = 0
    for _, _ in pairs(inventory) do
        count += 1
    end
    return count
end
 
local function getNextEmptySlot()
    local usedSlots = {}
    for _, data in ipairs(inventory) do
        usedSlots[data.slotIndex] = true
    end
    
    for i = 1, maxHotbarSlots do
        if not usedSlots[i] then return i end
    end
    
    local highest = maxHotbarSlots
    for i, _ in pairs(usedSlots) do
        if type(i) == "number" and i > highest then
            highest = i
        end
    end
    return highest + 1
end
 
local function isHoveringOver(uiElement, position)
    local pos = uiElement.AbsolutePosition
    local size = uiElement.AbsoluteSize
    return position.X >= pos.X and position.X <= pos.X + size.X and
           position.Y >= pos.Y and position.Y <= pos.Y + size.Y
end
 
local function setZIndexRecursive(obj, z)
    if obj:IsA("GuiObject") then
        obj.ZIndex = z
    end
    for _, child in ipairs(obj:GetChildren()) do
        setZIndexRecursive(child, z)
    end
end

-- ==========================================
-- CORE UI RENDERING
-- ==========================================
local function renderUI()
    for _, ui in ipairs(activeUIs) do
        ui:Destroy()
    end
    table.clear(activeUIs)
    
    local count = getToolCount()
    
    if menuButton then
        menuButton.Visible = (count > 0)
    end
    
    if count == 0 then
        isMenuOpen = false
        menuFrame.Visible = false
    end
    
    local usedHotbarSlots = {}
    for _, data in ipairs(inventory) do
        if data.slotIndex <= maxHotbarSlots then
            usedHotbarSlots[data.slotIndex] = true
        end
    end
    
    for i = 1, maxHotbarSlots do
        if isMenuOpen and not usedHotbarSlots[i] then
            displaySlots[i].Visible = true
        else
            displaySlots[i].Visible = false
        end
    end
    
    for _, data in ipairs(inventory) do
        local tool = data.tool
        local index = data.slotIndex
        
        local slot = slotTemplate:Clone()
        slot.Name = "Slot_" .. tool.Name
        slot.LayoutOrder = index
        slot.Size = originalSize
        slot.Visible = true
        
        if tool.TextureId and tool.TextureId ~= "" then
            slot.ToolIcon.Image = tool.TextureId
            slot.ToolIcon.Visible = true
            slot.ToolName.Visible = false
        else
            slot.ToolIcon.Visible = false
            slot.ToolName.Text = tool.Name
            slot.ToolName.Visible = true
        end
        
        if index <= maxHotbarSlots then
            slot.SlotNumber.Text = tostring(index)
            slot.SlotNumber.Visible = true
            slot.Parent = hotbarFrame
        else
            slot.SlotNumber.Visible = false
            slot.Parent = scrollingFrame
        end
        
        local stroke = slot:FindFirstChild("UIStroke")
        if stroke then
            stroke.Enabled = (equippedTool == tool)
        end
        
        table.insert(activeUIs, slot)

        -- Animasi Hover Logic
        slot.MouseEnter:Connect(function()
            if not isDragging then
                TweenService:Create(slot, tweenInfo, {Size = hoverSize}):Play()
            end
        end)
        slot.MouseLeave:Connect(function()
            TweenService:Create(slot, tweenInfo, {Size = originalSize}):Play()
        end)
        
        -- Input Logic (Equip & Drag)
        local holdTime = 0
        local isHolding = false
        local holdConn, moveConn
        
        slot.InputBegan:Connect(function(input)
            if isDragging then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isHolding = true
                holdTime = 0
                lastDragPosition = Vector2.new(input.Position.X, input.Position.Y)

                -- Efek hover buatan untuk Mobile saat disentuh
                if input.UserInputType == Enum.UserInputType.Touch then
                    TweenService:Create(slot, tweenInfo, {Size = hoverSize}):Play()
                end
                
                moveConn = UserInputService.InputChanged:Connect(function(moveInput)
                    if moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch then
                        local dist = (moveInput.Position - input.Position).Magnitude
                        if dist > 15 then
                            isHolding = false
                        end
                    end
                end)
                
                holdConn = RunService.Heartbeat:Connect(function(dt)
                    if not isHolding then
                        holdConn:Disconnect()
                        if moveConn then moveConn:Disconnect() end
                        return
                    end
                    
                    holdTime += dt
                    if holdTime >= 0.5 then
                        isHolding = false
                        holdConn:Disconnect()
                        if moveConn then moveConn:Disconnect() end
                        
                        -- START DRAGGING
                        isDragging = true
                        draggedToolData = data
                        
                        isMenuOpen = true
                        menuFrame.Visible = true
                        renderUI() 
                        
                        -- Setup Drag UI
                        dragUI = slotTemplate:Clone()
                        dragUI.Size = originalSize -- Kembali ke ukuran normal saat di-drag
                        dragUI.AnchorPoint = Vector2.new(0.5, 0.5)
                        dragUI.Parent = gui
                        dragUI.Visible = true
                        
                        -- FIX ZIndex saat di-drag agar selalu paling atas
                        setZIndexRecursive(dragUI, 99999) 
                        
                        if tool.TextureId ~= "" then
                            dragUI.ToolIcon.Image = tool.TextureId
                            dragUI.ToolIcon.Visible = true
                            dragUI.ToolName.Visible = false
                        else
                            dragUI.ToolIcon.Visible = false
                            dragUI.ToolName.Text = tool.Name
                            dragUI.ToolName.Visible = true
                        end
                        dragUI.SlotNumber.Visible = false
                        
                        for _, u in ipairs(activeUIs) do
                            if u.Name == "Slot_" .. tool.Name then
                                u.Visible = false
                            end
                        end
                        
                        currentInput = input
                        dragOffset = Vector2.new(slot.AbsoluteSize.X / 2, slot.AbsoluteSize.Y / 2)
                        
                        dragConnection = UserInputService.InputChanged:Connect(function(moveInput)
                            if not isDragging then return end
                            
                            if moveInput.UserInputType == Enum.UserInputType.Touch or moveInput.UserInputType == Enum.UserInputType.MouseMovement then
                                local pos = moveInput.Position
                                lastDragPosition = Vector2.new(pos.X, pos.Y) -- Track posisi akurat untuk Mobile
                                
                                dragUI.Position = UDim2.new(
                                    0, pos.X - dragOffset.X,
                                    0, pos.Y - dragOffset.Y
                                )
                            end
                        end)
                    end
                end)
            end
        end)
        
        slot.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isHolding = false
                if holdConn then holdConn:Disconnect() end
                if moveConn then moveConn:Disconnect() end
                
                -- Kembalikan ukuran normal jika di HP
                if input.UserInputType == Enum.UserInputType.Touch and not isDragging then
                    TweenService:Create(slot, tweenInfo, {Size = originalSize}):Play()
                end
                
                if holdTime < 0.5 and not isDragging then
                    local character = player.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        if equippedTool == tool then
                            humanoid:UnequipTools()
                            equippedTool = nil
                        else
                            humanoid:EquipTool(tool)
                            equippedTool = tool
                        end
                        renderUI()
                    end
                end
            end
        end)
    end
end
 
-- ==========================================
-- DROP LOGIC (DRAG & DROP)
-- ==========================================
UserInputService.InputEnded:Connect(function(input)
    if not isDragging then return end
    
    -- Tangkap baik Mouse klik lepas maupun jari diangkat
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = false
        if dragConnection then dragConnection:Disconnect() end
        if dragUI then dragUI:Destroy() end
        
        -- Menggunakan lastDragPosition yang dilacak secara real-time (SOLUSI MOBILE)
        local dropPos = lastDragPosition
        local targetSlotIndex = nil
        
        for i = 1, maxHotbarSlots do
            if displaySlots[i].Visible and isHoveringOver(displaySlots[i], dropPos) then
                targetSlotIndex = i
                break
            end
        end
        
        if not targetSlotIndex then
            if isHoveringOver(hotbarFrame, dropPos) or isHoveringOver(scrollingFrame, dropPos) then
                targetSlotIndex = getNextEmptySlot()
            end
        end
        
        if targetSlotIndex then
            draggedToolData.slotIndex = targetSlotIndex
            
            for _, data in ipairs(inventory) do
                if data ~= draggedToolData and data.slotIndex == targetSlotIndex then
                    data.slotIndex = getNextEmptySlot()
                end
            end
        else
            if draggedToolData.tool.CanBeDropped then
                draggedToolData.tool.Parent = workspace
            end
        end
        
        draggedToolData = nil
        renderUI()
    end
end)
 
-- ==========================================
-- MENU BUTTON LOGIC
-- ==========================================
if menuButton then
    menuButton.MouseButton1Click:Connect(function()
        if getToolCount() == 0 then return end
        isMenuOpen = not isMenuOpen
        menuFrame.Visible = isMenuOpen
        renderUI()
    end)
end
 
-- ==========================================
-- INVENTORY SYNCING
-- ==========================================
local function addTool(tool)
    for _, data in ipairs(inventory) do
        if data.tool == tool then return end
    end
    table.insert(inventory, {
        tool = tool,
        slotIndex = getNextEmptySlot()
    })
    renderUI()
end
 
local function removeTool(tool)
    for i, data in ipairs(inventory) do
        if data.tool == tool then
            table.remove(inventory, i)
            if equippedTool == tool then equippedTool = nil end
            break
        end
    end
    renderUI()
end
 
local function scanInventory()
    table.clear(inventory)
    for _, child in ipairs(backpack:GetChildren()) do
        if child:IsA("Tool") then addTool(child) end
    end
    if player.Character then
        local charTool = player.Character:FindFirstChildOfClass("Tool")
        if charTool then addTool(charTool) end
    end
end
 
-- ==========================================
-- CONNECTIONS
-- ==========================================
backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") then addTool(child) end
end)
 
backpack.ChildRemoved:Connect(function(child)
    if child:IsA("Tool") and child.Parent ~= player.Character then
        removeTool(child)
    end
end)
 
player.CharacterAdded:Connect(function(character)
    equippedTool = nil
    scanInventory()
    
    character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            equippedTool = child
            addTool(child)
        end
    end)
    
    character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child.Parent ~= backpack then
            removeTool(child)
        end
    end)
end)
 
if player.Character then
    player.Character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            equippedTool = child
            addTool(child)
        end
    end)
    player.Character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child.Parent ~= backpack then
            removeTool(child)
        end
    end)
end
 
-- Inisialisasi Pertama
scanInventory()
