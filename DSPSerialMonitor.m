function DSPSerialMonitor
% DSPSerialMonitor  Configurable-channel real-time serial waveform monitor.
%
% Expected DSP frame (one line per frame):
%   value1,value2,...,valueN
% Example:
%   48.12,75.03,8.42,7.91
%
% Default serial settings: COM10, 115200 baud, 8N1, no flow control.
% Requires MATLAB R2019b or newer (serialport interface).

maxChannelCount = 16;
defaultChannelCount = 4;
defaultPlotCount = 4;
defaultChannelNames = "CH" + string(1:maxChannelCount);
defaultChannelUnits = strings(1, maxChannelCount);
defaultYAxisExpand = true(1, maxChannelCount);
defaultYLimits = repmat([0 1], maxChannelCount, 1);
defaultChannelVisible = true(1, maxChannelCount);
defaultPlotIndex = mod(0:(maxChannelCount - 1), defaultPlotCount) + 1;
defaultColorPalette = [31 119 180; 255 127 14; 44 160 44; 214 39 40; ...
    148 103 189; 140 86 75; 227 119 194; 127 127 127; ...
    188 189 34; 23 190 207; 174 199 232; 255 187 120; ...
    152 223 138; 255 152 150; 197 176 213; 196 156 148] / 255;
yExpansionMargin = 0.05;
preferencesGroup = 'DSPSerialMonitor';
legacyPreferencesGroup = 'BoostSerialMonitor';
preferencesKey = 'ChannelDisplaySettings';
channelSettings = loadChannelSettings();
channelNames = channelSettings.names;
channelUnits = channelSettings.units;
defaultPort = "COM10";
defaultBaud = 115200;
maxStoredSamples = 360000; % About one hour at 100 samples/s.
plotPeriod = 0.05;         % Refresh plots at no more than 20 frames/s.
counterPeriod = 0.2;       % Refresh counters at no more than 5 frames/s.
maxPlotSamples = 2000;     % Limit graphics load for long time windows.
maxDspParameterCount = 32;
dspParameterPreferencesKey = 'DspParameterSettings';

% Only parameters in this whitelist can be written from MATLAB. The DSP
% firmware must apply the same whitelist and range checks independently.
dspParameters = loadDspParameters();

uiFontName = selectAvailableFont('Microsoft YaHei', ...
    {'Microsoft YaHei UI', 'SimHei', 'Noto Sans CJK SC', ...
    'Arial Unicode MS', 'Arial'});
plotFontName = selectAvailableFont('Times New Roman', ...
    {'Cambria', 'Georgia', 'Liberation Serif', 'DejaVu Serif', 'Arial'});
windowColor = [0.945 0.957 0.973];
cardColor = [1.000 1.000 1.000];
borderColor = [0.820 0.850 0.900];
textColor = [0.180 0.220 0.290];
mutedTextColor = [0.390 0.440 0.520];
primaryButtonColor = [0.110 0.400 0.780];
dangerButtonColor = [0.820 0.270 0.250];
warningButtonColor = [0.960 0.650 0.180];
secondaryButtonColor = [0.920 0.940 0.970];

state.serial = [];
state.connected = false;
state.paused = false;
state.time = zeros(maxStoredSamples, 1);
state.values = zeros(maxStoredSamples, channelSettings.channelCount);
state.sampleCount = 0;
state.writeIndex = 1;
state.goodFrames = 0;
state.badFrames = 0;
state.clock = tic;
state.timeOffset = 0;
state.lastPlotTime = -inf;
state.lastCounterTime = -inf;
state.closing = false;
state.settingsFigure = [];
state.settingsDraftData = {};
state.settingsDraftCount = channelSettings.channelCount;
state.settingsDraftColors = channelSettings.colors;
state.settingsDraftColorIsCustom = channelSettings.colorIsCustom;
state.settingsSelectedChannel = 1;
state.settingsColorButton = [];
state.currentYLimits = zeros(0, 2);
state.dspParameterFigure = [];
state.dspParameterTable = [];
state.dspParameterSendButton = [];
state.dspParameterConnectionLabel = [];
state.dspParameterCountLabel = [];
state.dspParameterAddButton = [];
state.dspParameterDeleteButton = [];
state.dspParameterRestoreButton = [];
state.dspParameterSelectedRow = 0;
state.txCount = 0;
state.txErrorCount = 0;
state.commandAckCount = 0;
state.commandErrorCount = 0;
state.lastCommand = '';
state.pendingCommand = '';
state.pendingVariable = '';
state.pendingValue = NaN;

fig = uifigure( ...
    'Name', 'DSP Serial Monitor', ...
    'Position', [100 80 1200 800], ...
    'Color', windowColor, ...
    'CloseRequestFcn', @onClose);

root = uigridlayout(fig, [3 1]);
root.RowHeight = {68, 32, '1x'};
root.Padding = [10 6 10 6];
root.RowSpacing = 4;
root.BackgroundColor = windowColor;

toolbar = uigridlayout(root, [1 3]);
toolbar.Layout.Row = 1;
toolbar.ColumnWidth = {350, '1x', 320};
toolbar.Padding = [0 0 0 0];
toolbar.ColumnSpacing = 10;
toolbar.BackgroundColor = windowColor;

settingsPanel = uipanel(toolbar, 'Title', '串口设置', ...
    'BackgroundColor', cardColor, 'BorderColor', borderColor, ...
    'FontName', uiFontName, 'FontSize', 12, 'FontWeight', 'bold', ...
    'ForegroundColor', textColor);
settingsPanel.Layout.Column = 1;
settingsGrid = uigridlayout(settingsPanel, [1 4]);
settingsGrid.ColumnWidth = {42, '1x', 52, 92};
settingsGrid.Padding = [10 2 10 4];
settingsGrid.ColumnSpacing = 7;
settingsGrid.BackgroundColor = cardColor;

uilabel(settingsGrid, 'Text', '串口', 'HorizontalAlignment', 'right', ...
    'FontName', uiFontName, 'FontSize', 12, 'FontColor', mutedTextColor);
portDropDown = uidropdown(settingsGrid, 'Items', {char(defaultPort)}, ...
    'Value', char(defaultPort), 'FontName', uiFontName, 'FontSize', 12);
uilabel(settingsGrid, 'Text', '波特率', 'HorizontalAlignment', 'right', ...
    'FontName', uiFontName, 'FontSize', 12, 'FontColor', mutedTextColor);
baudField = uieditfield(settingsGrid, 'numeric', 'Value', defaultBaud, ...
    'Limits', [300 inf], 'RoundFractionalValues', true, ...
    'FontName', uiFontName, 'FontSize', 12);

actionsPanel = uipanel(toolbar, 'Title', '采集控制', ...
    'BackgroundColor', cardColor, 'BorderColor', borderColor, ...
    'FontName', uiFontName, 'FontSize', 12, 'FontWeight', 'bold', ...
    'ForegroundColor', textColor);
actionsPanel.Layout.Column = 2;
actionsGrid = uigridlayout(actionsPanel, [1 7]);
actionsGrid.ColumnWidth = repmat({'1x'}, 1, 7);
actionsGrid.Padding = [10 2 10 4];
actionsGrid.ColumnSpacing = 7;
actionsGrid.BackgroundColor = cardColor;

refreshButton = uibutton(actionsGrid, 'Text', '刷新串口', ...
    'ButtonPushedFcn', @onRefreshPorts);
connectButton = uibutton(actionsGrid, 'Text', '连接', ...
    'ButtonPushedFcn', @onConnectToggle);
pauseButton = uibutton(actionsGrid, 'Text', '暂停显示', ...
    'Enable', 'off', 'ButtonPushedFcn', @onPauseToggle);
dspParameterButton = uibutton(actionsGrid, 'Text', 'DSP 参数', ...
    'Tag', 'DspParameterButton', ...
    'ButtonPushedFcn', @onOpenDspParameterSettings);
resetYAxisButton = uibutton(actionsGrid, 'Text', '重置Y轴', ...
    'ButtonPushedFcn', @onResetYAxis);
clearButton = uibutton(actionsGrid, 'Text', '清屏', ...
    'ButtonPushedFcn', @onClear);
saveButton = uibutton(actionsGrid, 'Text', '保存 CSV', ...
    'ButtonPushedFcn', @onSave);

secondaryButtons = [refreshButton, pauseButton, dspParameterButton, ...
    resetYAxisButton, clearButton, saveButton];
set(secondaryButtons, 'BackgroundColor', secondaryButtonColor, ...
    'FontColor', textColor, 'FontName', uiFontName, 'FontSize', 12);
set(connectButton, 'BackgroundColor', primaryButtonColor, ...
    'FontColor', cardColor, 'FontName', uiFontName, ...
    'FontSize', 12, 'FontWeight', 'bold');

displayPanel = uipanel(toolbar, 'Title', '显示设置', ...
    'BackgroundColor', cardColor, 'BorderColor', borderColor, ...
    'FontName', uiFontName, 'FontSize', 12, 'FontWeight', 'bold', ...
    'ForegroundColor', textColor);
displayPanel.Layout.Column = 3;
displayGrid = uigridlayout(displayPanel, [1 5]);
displayGrid.ColumnWidth = {60, 52, 48, 44, '1x'};
displayGrid.Padding = [10 2 10 4];
displayGrid.ColumnSpacing = 5;
displayGrid.BackgroundColor = cardColor;
uilabel(displayGrid, 'Text', '窗口 (s)', 'HorizontalAlignment', 'right', ...
    'FontName', uiFontName, 'FontSize', 12, 'FontColor', mutedTextColor);
windowField = uieditfield(displayGrid, 'numeric', 'Value', 10, ...
    'Limits', [0.5 3600], 'FontName', uiFontName, 'FontSize', 12);
uilabel(displayGrid, 'Text', '图表数', 'HorizontalAlignment', 'right', ...
    'FontName', uiFontName, 'FontSize', 12, 'FontColor', mutedTextColor);
plotCountDropDown = uidropdown(displayGrid, ...
    'Items', {'1', '2', '3', '4'}, ...
    'Value', char(string(channelSettings.plotCount)), ...
    'ValueChangedFcn', @onPlotCountChanged, ...
    'FontName', uiFontName, 'FontSize', 12);
uibutton(displayGrid, 'Text', '通道设置', ...
    'ButtonPushedFcn', @onOpenChannelSettings, ...
    'BackgroundColor', secondaryButtonColor, 'FontColor', textColor, ...
    'FontName', uiFontName, 'FontSize', 12);

statusPanel = uipanel(root, 'BackgroundColor', cardColor, ...
    'BorderColor', borderColor);
statusPanel.Layout.Row = 2;
statusGrid = uigridlayout(statusPanel, [1 5]);
statusGrid.ColumnWidth = {28, '1x', 135, 135, 175};
statusGrid.Padding = [10 2 10 2];
statusGrid.ColumnSpacing = 8;
statusGrid.BackgroundColor = cardColor;
statusLamp = uilamp(statusGrid, 'Color', [0.65 0.65 0.65]);
statusLabel = uilabel(statusGrid, 'Text', '未连接', ...
    'FontName', uiFontName, 'FontSize', 12, ...
    'FontWeight', 'bold', 'FontColor', mutedTextColor);
goodLabel = uilabel(statusGrid, 'Text', '有效帧: 0', ...
    'HorizontalAlignment', 'right', 'FontName', uiFontName, ...
    'FontSize', 12, 'FontColor', [0.180 0.560 0.360]);
badLabel = uilabel(statusGrid, 'Text', '异常帧: 0', ...
    'HorizontalAlignment', 'right', 'FontName', uiFontName, ...
    'FontSize', 12, 'FontColor', [0.760 0.280 0.260]);
sampleLabel = uilabel(statusGrid, 'Text', '缓存点数: 0', ...
    'HorizontalAlignment', 'right', 'FontName', uiFontName, ...
    'FontSize', 12, 'FontColor', mutedTextColor);

plots = uigridlayout(root, [1 1]);
plots.Layout.Row = 3;
plots.RowHeight = {'1x'};
plots.ColumnWidth = {'1x'};
plots.Padding = [0 0 0 0];
plots.RowSpacing = 4;
plots.ColumnSpacing = 10;
plots.BackgroundColor = windowColor;

axesHandles = gobjects(0, 1);
lineHandles = gobjects(channelSettings.channelCount, 1);

rebuildPlotLayout();
onRefreshPorts();

    function onRefreshPorts(~, ~)
        if state.connected
            return;
        end

        try
            availablePorts = string(serialportlist("available"));
            allPorts = string(serialportlist("all"));
        catch
            availablePorts = strings(0, 1);
            allPorts = strings(0, 1);
        end

        if isempty(allPorts)
            portDropDown.Items = {char(defaultPort)};
            portDropDown.Value = char(defaultPort);
            statusLabel.Text = 'Windows 未检测到串口';
            return;
        end

        % Show every Windows-enumerated port. A port that is listed by
        % "all" but not by "available" is normally busy or unusable.
        portDropDown.Items = cellstr(allPorts);
        if any(strcmpi(allPorts, defaultPort))
            portDropDown.Value = char(defaultPort);
        else
            portDropDown.Value = char(allPorts(1));
        end

        if isempty(availablePorts)
            statusLabel.Text = '检测到串口，但当前没有可打开的端口';
        else
            statusLabel.Text = sprintf('可用串口: %s', ...
                strjoin(cellstr(availablePorts), ', '));
        end
    end

    function onOpenChannelSettings(~, ~)
        if ~isempty(state.settingsFigure) && isvalid(state.settingsFigure)
            return;
        end

        dialogSize = [980 520];
        mainPosition = fig.Position;
        dialogPosition = [ ...
            mainPosition(1) + (mainPosition(3) - dialogSize(1)) / 2, ...
            mainPosition(2) + (mainPosition(4) - dialogSize(2)) / 2, ...
            dialogSize];
        state.settingsFigure = uifigure( ...
            'Name', '通道与 Y 轴设置', ...
            'Position', dialogPosition, ...
            'Color', windowColor, ...
            'WindowStyle', 'modal', ...
            'CloseRequestFcn', @(~, ~) closeChannelSettings());

        dialogRoot = uigridlayout(state.settingsFigure, [3 1]);
        dialogRoot.RowHeight = {42, '1x', 48};
        dialogRoot.Padding = [16 14 16 14];
        dialogRoot.RowSpacing = 10;
        dialogRoot.BackgroundColor = windowColor;

        headerGrid = uigridlayout(dialogRoot, [1 3]);
        headerGrid.Layout.Row = 1;
        headerGrid.ColumnWidth = {'1x', 65, 70};
        headerGrid.Padding = [0 0 0 0];
        headerGrid.ColumnSpacing = 8;
        headerGrid.BackgroundColor = windowColor;

        instructionLabel = uilabel(headerGrid, ...
            'Text', ['图号必须在当前图表数量范围内；Y 轴范围是最小显示范围，' ...
            '勾选超限扩展后，突变只会扩大范围。选择表格行可设置颜色。'], ...
            'FontName', uiFontName, 'FontSize', 12, ...
            'FontColor', mutedTextColor);
        instructionLabel.Layout.Column = 1;
        channelCountLabel = uilabel(headerGrid, 'Text', '通道数', ...
            'HorizontalAlignment', 'right', 'FontName', uiFontName, ...
            'FontSize', 12, 'FontColor', mutedTextColor);
        channelCountLabel.Layout.Column = 2;
        channelCountDropDown = uidropdown(headerGrid, ...
            'Items', cellstr(string(1:maxChannelCount)), ...
            'Value', char(string(channelSettings.channelCount)), ...
            'FontName', uiFontName, 'FontSize', 12);
        channelCountDropDown.Layout.Column = 3;
        if state.connected
            channelCountDropDown.Enable = 'off';
        end

        state.settingsDraftData = channelSettingsToTableData(channelSettings);
        state.settingsDraftCount = channelSettings.channelCount;
        state.settingsDraftColors = channelSettings.colors;
        state.settingsDraftColorIsCustom = channelSettings.colorIsCustom;
        state.settingsSelectedChannel = 1;
        rowNames = channelRowNames(state.settingsDraftCount);
        settingsTable = uitable(dialogRoot, ...
            'Data', state.settingsDraftData(1:state.settingsDraftCount, :), ...
            'ColumnName', {'名称', '单位', '显示', '图号', '颜色', ...
            '超限扩展', 'Y 最小值', 'Y 最大值'}, ...
            'ColumnEditable', [true true true true false true true true], ...
            'ColumnFormat', {'char', 'char', 'logical', 'numeric', 'char', ...
            'logical', 'numeric', 'numeric'}, ...
            'ColumnWidth', {150, 80, 55, 55, 85, 85, 95, 95}, ...
            'RowName', rowNames, ...
            'CellSelectionCallback', @onChannelTableSelection, ...
            'FontName', uiFontName, 'FontSize', 12, ...
            'BackgroundColor', [cardColor; 0.975 0.980 0.990]);
        settingsTable.Layout.Row = 2;
        channelCountDropDown.ValueChangedFcn = ...
            @(~, ~) onPendingChannelCountChanged( ...
            settingsTable, channelCountDropDown);

        dialogButtons = uigridlayout(dialogRoot, [1 5]);
        dialogButtons.Layout.Row = 3;
        dialogButtons.ColumnWidth = {'1x', 120, 120, 100, 100};
        dialogButtons.ColumnSpacing = 8;
        dialogButtons.Padding = [0 2 0 2];
        dialogButtons.BackgroundColor = windowColor;

        colorButton = uibutton(dialogButtons, 'Text', '选择颜色', ...
            'ButtonPushedFcn', @(~, ~) chooseChannelColor(settingsTable));
        colorButton.Layout.Column = 2;
        state.settingsColorButton = colorButton;
        restoreButton = uibutton(dialogButtons, 'Text', '恢复默认值', ...
            'ButtonPushedFcn', @(~, ~) restoreDefaultSettings( ...
            settingsTable, channelCountDropDown));
        restoreButton.Layout.Column = 3;
        cancelButton = uibutton(dialogButtons, 'Text', '取消', ...
            'ButtonPushedFcn', @(~, ~) closeChannelSettings());
        cancelButton.Layout.Column = 4;
        applyButton = uibutton(dialogButtons, 'Text', '应用', ...
            'ButtonPushedFcn', @(~, ~) applySettingsFromTable( ...
            settingsTable, channelCountDropDown));
        applyButton.Layout.Column = 5;

        set([colorButton, restoreButton, cancelButton], ...
            'BackgroundColor', secondaryButtonColor, ...
            'FontColor', textColor, 'FontName', uiFontName, 'FontSize', 12);
        set(applyButton, 'BackgroundColor', primaryButtonColor, ...
            'FontColor', cardColor, 'FontName', uiFontName, ...
            'FontSize', 12, 'FontWeight', 'bold');
        updateColorButton(state.settingsDraftColors(1, :));
    end

    function onChannelTableSelection(~, event)
        if isempty(event.Indices)
            return;
        end
        selectedRow = event.Indices(1, 1);
        if selectedRow >= 1 && selectedRow <= state.settingsDraftCount
            state.settingsSelectedChannel = selectedRow;
            updateColorButton(state.settingsDraftColors(selectedRow, :));
        end
    end

    function chooseChannelColor(settingsTable)
        channelIndex = state.settingsSelectedChannel;
        if channelIndex < 1 || channelIndex > state.settingsDraftCount
            return;
        end

        mainFigureForFocus = fig;
        settingsFigureForFocus = state.settingsFigure;
        focusCleanup = onCleanup(@() restoreMonitorWindowStack( ...
            mainFigureForFocus, settingsFigureForFocus));
        selectedColor = uisetcolor( ...
            state.settingsDraftColors(channelIndex, :), ...
            sprintf('选择 Channel %d 颜色', channelIndex));
        if isequal(selectedColor, 0)
            return;
        end

        state.settingsDraftColors(channelIndex, :) = selectedColor;
        state.settingsDraftColorIsCustom(channelIndex) = true;
        state.settingsDraftData{channelIndex, 5} = colorToHex(selectedColor);
        settingsTable.Data = ...
            state.settingsDraftData(1:state.settingsDraftCount, :);
        updateColorButton(selectedColor);
    end

    function onPendingChannelCountChanged(settingsTable, channelCountDropDown)
        state.settingsDraftData(1:state.settingsDraftCount, :) = ...
            settingsTable.Data;
        pendingCount = str2double(channelCountDropDown.Value);
        state.settingsDraftCount = pendingCount;
        settingsTable.Data = state.settingsDraftData(1:pendingCount, :);
        settingsTable.RowName = channelRowNames(pendingCount);
        state.settingsSelectedChannel = min( ...
            state.settingsSelectedChannel, pendingCount);
        updateColorButton(state.settingsDraftColors( ...
            state.settingsSelectedChannel, :));
    end

    function restoreDefaultSettings(settingsTable, channelCountDropDown)
        settings = defaultChannelSettings();
        settings.plotCount = channelSettings.plotCount;
        settings.plotIndex = min(settings.plotIndex, settings.plotCount);
        pendingCount = str2double(channelCountDropDown.Value);
        settings.channelCount = pendingCount;
        settings = assignAutomaticColors(settings);
        state.settingsDraftData = channelSettingsToTableData(settings);
        state.settingsDraftCount = pendingCount;
        state.settingsDraftColors = settings.colors;
        state.settingsDraftColorIsCustom = settings.colorIsCustom;
        state.settingsSelectedChannel = min( ...
            state.settingsSelectedChannel, pendingCount);
        settingsTable.Data = state.settingsDraftData(1:pendingCount, :);
        settingsTable.RowName = channelRowNames(pendingCount);
        updateColorButton(state.settingsDraftColors( ...
            state.settingsSelectedChannel, :));
    end

    function applySettingsFromTable(settingsTable, channelCountDropDown)
        state.settingsDraftData(1:state.settingsDraftCount, :) = ...
            settingsTable.Data;
        pendingCount = str2double(channelCountDropDown.Value);
        if pendingCount ~= channelSettings.channelCount
            if state.connected
                uialert(state.settingsFigure, ...
                    '请先断开串口连接，再修改通道数量。', '无法修改通道数');
                return;
            end
            if state.sampleCount > 0
                uialert(state.settingsFigure, ...
                    ['修改通道数前，请先保存需要的数据，然后使用“清屏”' ...
                    '清空当前缓存。'], '缓存非空');
                return;
            end
        end

        data = state.settingsDraftData;
        try
            names = strtrim(string(data(:, 1))).';
            units = strtrim(string(data(:, 2))).';
            visible = logical(cell2mat(data(:, 3))).';
            plotIndex = double(cell2mat(data(:, 4))).';
            expandY = logical(cell2mat(data(:, 6))).';
            minimums = double(cell2mat(data(:, 7)));
            maximums = double(cell2mat(data(:, 8)));
        catch
            uialert(state.settingsFigure, ...
                '请检查表格内容，上下限必须为数值。', '设置无效');
            return;
        end

        if any(strlength(names) == 0)
            uialert(state.settingsFigure, ...
                '所有通道的名称均不能为空。', '设置无效');
            return;
        end

        if any(~isfinite(plotIndex)) || any(plotIndex ~= round(plotIndex)) || ...
                any(plotIndex < 1) || any(plotIndex > channelSettings.plotCount)
            uialert(state.settingsFigure, ...
                sprintf('图号必须是 1 到 %d 之间的整数。', ...
                channelSettings.plotCount), '设置无效');
            return;
        end

        yLimits = [minimums(:) maximums(:)];
        if any(~isfinite(yLimits), 'all') || any(yLimits(:, 1) >= yLimits(:, 2))
            uialert(state.settingsFigure, ...
                'Y 轴上下限必须为有限数值，且最小值必须小于最大值。', ...
                '设置无效');
            return;
        end

        channelSettings.names = names;
        channelSettings.units = units;
        channelSettings.visible = visible;
        channelSettings.plotIndex = plotIndex;
        channelSettings.expandY = expandY;
        channelSettings.yLimits = yLimits;
        channelSettings.colors = state.settingsDraftColors;
        channelSettings.colorIsCustom = ...
            state.settingsDraftColorIsCustom;
        channelCountChanged = pendingCount ~= channelSettings.channelCount;
        channelSettings.channelCount = pendingCount;
        channelSettings = assignAutomaticColors(channelSettings);
        state.settingsDraftColors = channelSettings.colors;
        state.settingsDraftColorIsCustom = channelSettings.colorIsCustom;
        state.settingsDraftData = channelSettingsToTableData(channelSettings);
        settingsTable.Data = ...
            state.settingsDraftData(1:pendingCount, :);
        updateColorButton(state.settingsDraftColors( ...
            state.settingsSelectedChannel, :));
        channelNames = names;
        channelUnits = units;
        if channelCountChanged
            resetAcquisitionData(pendingCount);
        end
        rebuildPlotLayout();
        if channelCountChanged
            updateCounters(true);
        end

        [saved, errorMessage] = saveChannelSettings();
        if ~saved
            uialert(state.settingsFigure, ...
                ['设置已应用，但无法保存到 MATLAB 首选项。' newline ...
                errorMessage], '保存设置失败');
            return;
        end

        statusLabel.Text = '通道显示设置已更新';
        closeChannelSettings();
    end

    function closeChannelSettings()
        if ~isempty(state.settingsFigure) && isvalid(state.settingsFigure)
            delete(state.settingsFigure);
        end
        state.settingsFigure = [];
        state.settingsDraftData = {};
        state.settingsDraftCount = channelSettings.channelCount;
        state.settingsDraftColors = channelSettings.colors;
        state.settingsDraftColorIsCustom = channelSettings.colorIsCustom;
        state.settingsSelectedChannel = 1;
        state.settingsColorButton = [];
    end

    function onOpenDspParameterSettings(~, ~)
        if ~isempty(state.dspParameterFigure) && ...
                isvalid(state.dspParameterFigure)
            figure(state.dspParameterFigure);
            return;
        end

        state.dspParameterSelectedRow = 0;
        dialogSize = [900 440];
        mainPosition = fig.Position;
        dialogPosition = [ ...
            mainPosition(1) + (mainPosition(3) - dialogSize(1)) / 2, ...
            mainPosition(2) + (mainPosition(4) - dialogSize(2)) / 2, ...
            dialogSize];
        state.dspParameterFigure = uifigure( ...
            'Name', 'DSP 参数控制', ...
            'Tag', 'DspParameterFigure', ...
            'Position', dialogPosition, ...
            'Color', windowColor, ...
            'CloseRequestFcn', @(~, ~) closeDspParameterSettings());

        dialogRoot = uigridlayout(state.dspParameterFigure, [3 1]);
        dialogRoot.RowHeight = {50, '1x', 48};
        dialogRoot.Padding = [16 14 16 14];
        dialogRoot.RowSpacing = 10;
        dialogRoot.BackgroundColor = windowColor;

        headerGrid = uigridlayout(dialogRoot, [2 2]);
        headerGrid.Layout.Row = 1;
        headerGrid.RowHeight = {24, 20};
        headerGrid.ColumnWidth = {'1x', 90};
        headerGrid.Padding = [0 0 0 0];
        headerGrid.RowSpacing = 2;
        headerGrid.ColumnSpacing = 8;
        headerGrid.BackgroundColor = windowColor;
        instructionLabel = uilabel(headerGrid, ...
            'Text', ['可编辑参数名称、值、单位和范围；只有收到 DSP 的 ' ...
            'ACK 才表示写入成功。'], ...
            'FontName', uiFontName, 'FontSize', 12, ...
            'FontWeight', 'bold', 'FontColor', textColor);
        instructionLabel.Layout.Row = 1;
        instructionLabel.Layout.Column = [1 2];
        state.dspParameterConnectionLabel = uilabel(headerGrid, ...
            'Text', '', 'FontName', uiFontName, 'FontSize', 11, ...
            'FontColor', mutedTextColor);
        state.dspParameterConnectionLabel.Layout.Row = 2;
        state.dspParameterConnectionLabel.Layout.Column = 1;
        state.dspParameterCountLabel = uilabel(headerGrid, ...
            'Text', '', 'HorizontalAlignment', 'right', ...
            'FontName', uiFontName, 'FontSize', 11, ...
            'FontColor', mutedTextColor);
        state.dspParameterCountLabel.Layout.Row = 2;
        state.dspParameterCountLabel.Layout.Column = 2;

        state.dspParameterTable = uitable(dialogRoot, ...
            'Tag', 'DspParameterTable', ...
            'Data', dspParameterTableData(), ...
            'ColumnName', {'参数名称', '当前设定值', '单位', ...
            '最小值', '最大值', '状态'}, ...
            'ColumnEditable', [true true true true true false], ...
            'ColumnFormat', {'char', 'numeric', 'char', 'numeric', ...
            'numeric', 'char'}, ...
            'ColumnWidth', {175, 115, 80, 95, 95, 125}, ...
            'RowName', [], ...
            'CellSelectionCallback', @onDspParameterSelection, ...
            'CellEditCallback', @onDspParameterEdit, ...
            'FontName', uiFontName, 'FontSize', 12, ...
            'BackgroundColor', [cardColor; 0.975 0.980 0.990]);
        state.dspParameterTable.Layout.Row = 2;

        dialogButtons = uigridlayout(dialogRoot, [1 6]);
        dialogButtons.Layout.Row = 3;
        dialogButtons.ColumnWidth = {'1x', 105, 115, 105, 150, 90};
        dialogButtons.ColumnSpacing = 8;
        dialogButtons.Padding = [0 2 0 2];
        dialogButtons.BackgroundColor = windowColor;
        state.dspParameterAddButton = uibutton(dialogButtons, ...
            'Text', '新增参数', 'Tag', 'DspParameterAddButton', ...
            'ButtonPushedFcn', @onAddDspParameter, ...
            'BackgroundColor', secondaryButtonColor, ...
            'FontColor', textColor, 'FontName', uiFontName, 'FontSize', 12);
        state.dspParameterAddButton.Layout.Column = 2;
        state.dspParameterDeleteButton = uibutton(dialogButtons, ...
            'Text', '删除选中', 'Tag', 'DspParameterDeleteButton', ...
            'ButtonPushedFcn', @onDeleteDspParameter, ...
            'BackgroundColor', secondaryButtonColor, ...
            'FontColor', textColor, 'FontName', uiFontName, 'FontSize', 12);
        state.dspParameterDeleteButton.Layout.Column = 3;
        state.dspParameterRestoreButton = uibutton(dialogButtons, ...
            'Text', '恢复默认', 'Tag', 'DspParameterRestoreButton', ...
            'ButtonPushedFcn', @onRestoreDefaultDspParameters, ...
            'BackgroundColor', secondaryButtonColor, ...
            'FontColor', textColor, 'FontName', uiFontName, 'FontSize', 12);
        state.dspParameterRestoreButton.Layout.Column = 4;
        state.dspParameterSendButton = uibutton(dialogButtons, ...
            'Text', '发送选中参数', ...
            'Tag', 'DspParameterSendButton', ...
            'ButtonPushedFcn', @onSendSelectedDspParameter, ...
            'BackgroundColor', primaryButtonColor, ...
            'FontColor', cardColor, 'FontName', uiFontName, ...
            'FontSize', 12, 'FontWeight', 'bold');
        state.dspParameterSendButton.Layout.Column = 5;
        closeButton = uibutton(dialogButtons, 'Text', '关闭', ...
            'ButtonPushedFcn', @(~, ~) closeDspParameterSettings(), ...
            'BackgroundColor', secondaryButtonColor, ...
            'FontColor', textColor, 'FontName', uiFontName, 'FontSize', 12);
        closeButton.Layout.Column = 6;
        updateDspParameterControls();
    end

    function onDspParameterSelection(~, event)
        if isempty(event.Indices)
            return;
        end
        selectedRow = event.Indices(1, 1);
        if selectedRow >= 1 && selectedRow <= numel(dspParameters.names)
            state.dspParameterSelectedRow = selectedRow;
            updateDspParameterButtonStates();
        end
    end

    function onDspParameterEdit(~, event)
        if isempty(event.Indices) || event.Indices(1, 2) > 5
            return;
        end

        parameterIndex = event.Indices(1, 1);
        columnIndex = event.Indices(1, 2);
        state.dspParameterSelectedRow = parameterIndex;
        variableName = dspParameters.names(parameterIndex);
        if strcmp(state.pendingVariable, char(variableName))
            updateDspParameterControls();
            uialert(state.dspParameterFigure, ...
                '该参数正在等待 DSP 确认，暂时不能修改。', '参数等待确认');
            return;
        end

        pendingParameters = dspParameters;
        switch columnIndex
            case 1
                pendingParameters.names(parameterIndex) = ...
                    strtrim(string(event.NewData));
            case 2
                pendingParameters.values(parameterIndex) = ...
                    numericDspParameterValue(event.NewData);
            case 3
                pendingParameters.units(parameterIndex) = ...
                    strtrim(string(event.NewData));
            case 4
                pendingParameters.minimums(parameterIndex) = ...
                    numericDspParameterValue(event.NewData);
            case 5
                pendingParameters.maximums(parameterIndex) = ...
                    numericDspParameterValue(event.NewData);
        end

        [validSettings, errorMessage] = ...
            isValidDspParameterSettings(pendingParameters);
        if ~validSettings
            updateDspParameterControls();
            uialert(state.dspParameterFigure, errorMessage, '参数无效');
            return;
        end

        dspParameters = pendingParameters;
        dspParameters.confirmedValues(parameterIndex) = NaN;
        dspParameters.statuses(parameterIndex) = "未发送";
        updateDspParameterControls();
        saveDspParameterSettingsWithAlert();
    end

    function onAddDspParameter(~, ~)
        if ~isempty(state.pendingCommand) || ...
                numel(dspParameters.names) >= maxDspParameterCount
            return;
        end

        parameterNumber = 1;
        while any(strcmpi(dspParameters.names, ...
                "PARAM_" + string(parameterNumber)))
            parameterNumber = parameterNumber + 1;
        end
        dspParameters.names(end + 1) = "PARAM_" + string(parameterNumber);
        dspParameters.units(end + 1) = "";
        dspParameters.minimums(end + 1) = 0;
        dspParameters.maximums(end + 1) = 1;
        dspParameters.values(end + 1) = 0;
        dspParameters.confirmedValues(end + 1) = NaN;
        dspParameters.statuses(end + 1) = "未发送";
        state.dspParameterSelectedRow = numel(dspParameters.names);
        updateDspParameterControls();
        saveDspParameterSettingsWithAlert();
        statusLabel.Text = sprintf('已新增参数 %s', ...
            char(dspParameters.names(end)));
    end

    function onDeleteDspParameter(~, ~)
        parameterCount = numel(dspParameters.names);
        parameterIndex = state.dspParameterSelectedRow;
        if ~isempty(state.pendingCommand) || parameterCount <= 1 || ...
                parameterIndex < 1 || parameterIndex > parameterCount
            return;
        end

        variableName = dspParameters.names(parameterIndex);
        choice = uiconfirm(state.dspParameterFigure, sprintf( ...
            '确定删除参数 %s 吗？', char(variableName)), ...
            '删除 DSP 参数', 'Options', {'删除', '取消'}, ...
            'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(choice, '删除')
            return;
        end

        keepIndices = true(1, parameterCount);
        keepIndices(parameterIndex) = false;
        dspParameters.names = dspParameters.names(keepIndices);
        dspParameters.units = dspParameters.units(keepIndices);
        dspParameters.minimums = dspParameters.minimums(keepIndices);
        dspParameters.maximums = dspParameters.maximums(keepIndices);
        dspParameters.values = dspParameters.values(keepIndices);
        dspParameters.confirmedValues = ...
            dspParameters.confirmedValues(keepIndices);
        dspParameters.statuses = dspParameters.statuses(keepIndices);
        state.dspParameterSelectedRow = 0;
        updateDspParameterControls();
        saveDspParameterSettingsWithAlert();
        statusLabel.Text = sprintf('已删除参数 %s', char(variableName));
    end

    function onRestoreDefaultDspParameters(~, ~)
        if ~isempty(state.pendingCommand)
            return;
        end
        choice = uiconfirm(state.dspParameterFigure, ...
            '确定恢复默认的四个 DSP 参数吗？当前自定义清单将被替换。', ...
            '恢复默认参数', 'Options', {'恢复默认', '取消'}, ...
            'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(choice, '恢复默认')
            return;
        end

        dspParameters = defaultDspParameters();
        state.dspParameterSelectedRow = 0;
        updateDspParameterControls();
        saveDspParameterSettingsWithAlert();
        statusLabel.Text = 'DSP 参数清单已恢复默认值';
    end

    function onSendSelectedDspParameter(~, ~)
        parameterIndex = state.dspParameterSelectedRow;
        if parameterIndex < 1 || ...
                parameterIndex > numel(dspParameters.names)
            return;
        end
        sendDspParameter(dspParameters.names(parameterIndex), ...
            dspParameters.values(parameterIndex));
    end

    function sendDspParameter(variableName, value)
        if ~state.connected || isempty(state.serial)
            updateDspParameterControls();
            uialert(state.dspParameterFigure, ...
                '请先连接串口，再发送 DSP 参数。', '串口未连接');
            return;
        end
        if ~isempty(state.pendingCommand)
            statusLabel.Text = sprintf('正在等待 %s 的 DSP 确认', ...
                state.pendingVariable);
            return;
        end

        parameterIndex = findDspParameter(variableName);
        if isempty(parameterIndex) || ~isscalar(value) || ...
                ~isfinite(value) || ...
                value < dspParameters.minimums(parameterIndex) || ...
                value > dspParameters.maximums(parameterIndex)
            state.txErrorCount = state.txErrorCount + 1;
            statusLabel.Text = 'DSP 参数未通过本地白名单或范围检查';
            return;
        end

        command = sprintf('SET,%s,%.15g', char(variableName), value);
        state.lastCommand = command;
        state.pendingCommand = command;
        state.pendingVariable = char(variableName);
        state.pendingValue = value;
        dspParameters.statuses(parameterIndex) = "等待确认";
        updateDspParameterControls();
        statusLabel.Text = sprintf('已发送 %s，等待 DSP 确认', command);

        try
            writeline(state.serial, command);
            state.txCount = state.txCount + 1;
        catch exception
            state.txErrorCount = state.txErrorCount + 1;
            dspParameters.statuses(parameterIndex) = "写入失败";
            clearPendingCommand();
            updateDspParameterControls();
            statusLabel.Text = ['参数发送失败: ' exception.message];
            uialert(state.dspParameterFigure, exception.message, ...
                '参数发送失败');
        end
    end

    function parameterIndex = findDspParameter(variableName)
        parameterIndex = find(strcmp(dspParameters.names, ...
            string(variableName)), 1);
    end

    function updateDspParameterControls()
        if isempty(state.dspParameterFigure) || ...
                ~isvalid(state.dspParameterFigure)
            return;
        end
        if ~isempty(state.dspParameterTable) && ...
                isvalid(state.dspParameterTable)
            state.dspParameterTable.Data = dspParameterTableData();
        end
        updateDspParameterButtonStates();
    end

    function updateDspParameterButtonStates()
        if isempty(state.dspParameterFigure) || ...
                ~isvalid(state.dspParameterFigure)
            return;
        end
        parameterCount = numel(dspParameters.names);
        validSelection = state.dspParameterSelectedRow >= 1 && ...
            state.dspParameterSelectedRow <= parameterCount;
        noPendingCommand = isempty(state.pendingCommand);
        if ~isempty(state.dspParameterSendButton) && ...
                isvalid(state.dspParameterSendButton)
            if state.connected && noPendingCommand && validSelection
                state.dspParameterSendButton.Enable = 'on';
            else
                state.dspParameterSendButton.Enable = 'off';
            end
        end
        if ~isempty(state.dspParameterAddButton) && ...
                isvalid(state.dspParameterAddButton)
            if noPendingCommand && parameterCount < maxDspParameterCount
                state.dspParameterAddButton.Enable = 'on';
            else
                state.dspParameterAddButton.Enable = 'off';
            end
        end
        if ~isempty(state.dspParameterDeleteButton) && ...
                isvalid(state.dspParameterDeleteButton)
            if noPendingCommand && parameterCount > 1 && validSelection
                state.dspParameterDeleteButton.Enable = 'on';
            else
                state.dspParameterDeleteButton.Enable = 'off';
            end
        end
        if ~isempty(state.dspParameterRestoreButton) && ...
                isvalid(state.dspParameterRestoreButton)
            if noPendingCommand
                state.dspParameterRestoreButton.Enable = 'on';
            else
                state.dspParameterRestoreButton.Enable = 'off';
            end
        end
        if ~isempty(state.dspParameterCountLabel) && ...
                isvalid(state.dspParameterCountLabel)
            state.dspParameterCountLabel.Text = sprintf('%d / %d', ...
                parameterCount, maxDspParameterCount);
        end
        if ~isempty(state.dspParameterConnectionLabel) && ...
                isvalid(state.dspParameterConnectionLabel)
            if state.connected
                if noPendingCommand
                    if state.dspParameterSelectedRow == 0
                        state.dspParameterConnectionLabel.Text = ...
                            '串口已连接，请在表格中选择一个参数。';
                    else
                        state.dspParameterConnectionLabel.Text = ...
                            '串口已连接，可以发送选中参数。';
                    end
                    state.dspParameterConnectionLabel.FontColor = ...
                        [0.180 0.560 0.360];
                else
                    state.dspParameterConnectionLabel.Text = sprintf( ...
                        '等待 DSP 确认：%s', state.pendingVariable);
                    state.dspParameterConnectionLabel.FontColor = ...
                        warningButtonColor;
                end
            else
                state.dspParameterConnectionLabel.Text = ...
                    '串口未连接：可以编辑参数，但暂时不能发送。';
                state.dspParameterConnectionLabel.FontColor = ...
                    mutedTextColor;
            end
        end
    end

    function data = dspParameterTableData()
        parameterCount = numel(dspParameters.names);
        data = cell(parameterCount, 6);
        for parameterIndex = 1:parameterCount
            data{parameterIndex, 1} = ...
                char(dspParameters.names(parameterIndex));
            data{parameterIndex, 2} = ...
                dspParameters.values(parameterIndex);
            data{parameterIndex, 3} = ...
                char(dspParameters.units(parameterIndex));
            data{parameterIndex, 4} = ...
                dspParameters.minimums(parameterIndex);
            data{parameterIndex, 5} = ...
                dspParameters.maximums(parameterIndex);
            data{parameterIndex, 6} = ...
                char(dspParameters.statuses(parameterIndex));
        end
    end

    function clearPendingCommand()
        state.pendingCommand = '';
        state.pendingVariable = '';
        state.pendingValue = NaN;
    end

    function closeDspParameterSettings()
        if ~isempty(state.dspParameterFigure) && ...
                isvalid(state.dspParameterFigure)
            delete(state.dspParameterFigure);
        end
        state.dspParameterFigure = [];
        state.dspParameterTable = [];
        state.dspParameterSendButton = [];
        state.dspParameterConnectionLabel = [];
        state.dspParameterCountLabel = [];
        state.dspParameterAddButton = [];
        state.dspParameterDeleteButton = [];
        state.dspParameterRestoreButton = [];
        state.dspParameterSelectedRow = 0;
    end

    function onPlotCountChanged(~, ~)
        plotCount = str2double(plotCountDropDown.Value);
        if ~isfinite(plotCount) || plotCount ~= round(plotCount) || ...
                plotCount < 1 || plotCount > 4
            plotCountDropDown.Value = char(string(channelSettings.plotCount));
            uialert(fig, '图表数量必须是 1 到 4 之间的整数。', '设置无效');
            return;
        end

        channelSettings.plotCount = plotCount;
        channelSettings.plotIndex = min(channelSettings.plotIndex, plotCount);
        channelSettings = assignAutomaticColors(channelSettings);
        rebuildPlotLayout();
        [saved, errorMessage] = saveChannelSettings();
        if saved
            statusLabel.Text = sprintf('图表数量已更新为 %d', plotCount);
        else
            uialert(fig, ['图表布局已应用，但无法保存到 MATLAB 首选项。' ...
                newline errorMessage], '保存设置失败');
        end
    end

    function rebuildPlotLayout()
        % Axes belong to plots, while each line continues to represent one
        % fixed input channel and is recreated only when display mapping changes.
        delete(plots.Children);
        plotCount = channelSettings.plotCount;
        rowCount = plotCount;
        columnCount = 1;

        plots.RowHeight = repmat({'1x'}, 1, rowCount);
        plots.ColumnWidth = repmat({'1x'}, 1, columnCount);
        axesHandles = gobjects(plotCount, 1);
        lineHandles = gobjects(channelSettings.channelCount, 1);

        for plotIndex = 1:plotCount
            ax = uiaxes(plots);
            ax.Layout.Row = plotIndex;
            ax.Layout.Column = 1;
            configurePlotAxes(ax);
            axesHandles(plotIndex) = ax;
        end

        for channelIndex = 1:channelSettings.channelCount
            plotIndex = channelSettings.plotIndex(channelIndex);
            ax = axesHandles(plotIndex);
            lineHandles(channelIndex) = plot(ax, NaN, NaN, ...
                'LineWidth', 1.5, ...
                'Color', channelSettings.colors(channelIndex, :), ...
                'DisplayName', char(channelNames(channelIndex)));
            if channelSettings.visible(channelIndex)
                lineHandles(channelIndex).Visible = 'on';
            else
                lineHandles(channelIndex).Visible = 'off';
            end
        end

        updatePlotLabelsAndLegends();
        resetYAxisRanges();
        if state.sampleCount > 0
            updatePlots();
        end
    end

    function configurePlotAxes(ax)
        ax.Box = 'on';
        ax.Color = cardColor;
        ax.FontName = plotFontName;
        ax.FontSize = 10;
        ax.XColor = mutedTextColor;
        ax.YColor = mutedTextColor;
        ax.LineWidth = 0.8;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridColor = borderColor;
        ax.GridAlpha = 0.28;
        xlabel(ax, 'Time (s)');
        ylabel(ax, 'Value');
        hold(ax, 'on');
        ax.Title.FontName = plotFontName;
        ax.Title.FontSize = 14;
        ax.Title.FontWeight = 'bold';
        ax.Title.Color = textColor;
        ax.XLabel.FontName = plotFontName;
        ax.XLabel.FontSize = 11;
        ax.XLabel.Color = mutedTextColor;
        ax.YLabel.FontName = plotFontName;
        ax.YLabel.FontSize = 11;
        ax.YLabel.Color = mutedTextColor;
    end

    function updatePlotLabelsAndLegends()
        activeChannels = 1:channelSettings.channelCount;
        for plotIndex = 1:channelSettings.plotCount
            channelIndices = activeChannels( ...
                channelSettings.visible(activeChannels) & ...
                channelSettings.plotIndex(activeChannels) == plotIndex);
            ax = axesHandles(plotIndex);
            if isempty(channelIndices)
                ax.Title.String = sprintf('Plot %d', plotIndex);
                ax.YLabel.String = 'Value';
                legend(ax, 'off');
                continue;
            end

            ax.Title.String = strjoin(cellstr(channelNames(channelIndices)), ' / ');
            plotUnits = channelUnits(channelIndices);
            if all(strlength(plotUnits) > 0) && all(plotUnits == plotUnits(1))
                ax.YLabel.String = plotUnits(1);
            else
                ax.YLabel.String = 'Value';
            end

            if numel(channelIndices) >= 2
                legendHandle = legend(ax, lineHandles(channelIndices), ...
                    cellstr(channelNames(channelIndices)), 'Location', 'best');
                legendHandle.FontName = plotFontName;
            else
                legend(ax, 'off');
            end
        end
    end

    function onConnectToggle(~, ~)
        if state.connected
            disconnectSerial('已断开');
            return;
        end

        port = string(portDropDown.Value);
        baud = round(baudField.Value);
        connectButton.Enable = 'off';
        statusLabel.Text = '正在连接...';
        drawnow;

        sp = [];
        try
            % Open with the minimum argument set first. Some USB-UART
            % drivers reject a constructor that negotiates every property
            % at once even though the basic port can be opened.
            sp = serialport(char(port), baud);
            sp.DataBits = 8;
            sp.StopBits = 1;
            sp.Parity = 'none';
            sp.FlowControl = 'none';
            sp.Timeout = 1;
            configureTerminator(sp, "LF");
            flush(sp);

            state.serial = sp;
            state.connected = true;
            state.timeOffset = latestSampleTime();
            state.clock = tic;
            state.lastPlotTime = -inf;
            configureCallback(sp, "terminator", @onSerialLine);

            connectButton.Text = '断开';
            connectButton.Enable = 'on';
            connectButton.BackgroundColor = dangerButtonColor;
            refreshButton.Enable = 'off';
            portDropDown.Enable = 'off';
            baudField.Enable = 'off';
            pauseButton.Enable = 'on';
            statusLamp.Color = [0.18 0.72 0.34];
            statusLabel.Text = sprintf('已连接 %s @ %d baud', port, baud);
            updateDspParameterControls();
        catch exception
            if ~isempty(sp)
                try
                    configureCallback(sp, "off");
                catch
                end
                clear sp
            end
            state.serial = [];
            state.connected = false;
            connectButton.Enable = 'on';
            connectButton.BackgroundColor = primaryButtonColor;
            statusLamp.Color = [0.85 0.25 0.20];
            statusLabel.Text = '连接失败';
            updateDspParameterControls();
            diagnosis = buildSerialDiagnosis(port, baud, exception);
            uialert(fig, diagnosis, '串口连接失败');
        end
    end

    function message = buildSerialDiagnosis(port, baud, exception)
        try
            allPorts = string(serialportlist("all"));
            availablePorts = string(serialportlist("available"));
        catch
            allPorts = strings(0, 1);
            availablePorts = strings(0, 1);
        end

        allText = portListText(allPorts);
        availableText = portListText(availablePorts);
        if any(strcmpi(availablePorts, port))
            conclusion = '端口被枚举为可用；请检查下方 MATLAB/驱动原始错误。';
        elseif any(strcmpi(allPorts, port))
            conclusion = ['Windows 能看到该端口，但 MATLAB 判定它不可打开。' ...
                '常见原因是驱动异常或其他进程占用。'];
        else
            conclusion = 'Windows 当前未枚举到所选端口，请重新插拔并刷新串口。';
        end

        message = sprintf([ ...
            '目标: %s @ %d baud\n' ...
            '全部端口: %s\n' ...
            '可用端口: %s\n\n' ...
            '判断: %s\n\n' ...
            'MATLAB 错误标识: %s\n' ...
            '原始错误: %s'], ...
            char(port), baud, allText, availableText, conclusion, ...
            exception.identifier, exception.message);
    end

    function output = portListText(ports)
        if isempty(ports)
            output = '无';
        else
            output = strjoin(cellstr(ports), ', ');
        end
    end

    function onSerialLine(source, ~)
        if state.closing || ~state.connected
            return;
        end

        try
            rawLine = strtrim(readline(source));
            processSerialMessage(rawLine);
        catch exception
            state.badFrames = state.badFrames + 1;
            updateCounters(false);
            if state.connected
                statusLabel.Text = ['接收异常: ' exception.message];
            end
        end
    end

    function processSerialMessage(rawLine)
        fields = strtrim(split(rawLine, ','));
        messageType = fields(1);
        if strcmp(messageType, "ACK")
            try
                processAckMessage(fields);
            catch exception
                registerControlProtocolError( ...
                    ['ACK 处理失败: ' exception.message]);
            end
        elseif strcmp(messageType, "ERR")
            try
                processErrorMessage(fields);
            catch exception
                registerControlProtocolError( ...
                    ['ERR 处理失败: ' exception.message]);
            end
        else
            processDataFrame(fields);
        end
    end

    function processDataFrame(fields)
        values = str2double(fields);
        channelCount = channelSettings.channelCount;
        if numel(values) ~= channelCount || any(~isfinite(values))
            state.badFrames = state.badFrames + 1;
            updateCounters(false);
            return;
        end

        elapsed = state.timeOffset + toc(state.clock);
        sampleValues = reshape(values, 1, channelCount);
        state.time(state.writeIndex) = elapsed;
        state.values(state.writeIndex, :) = sampleValues;
        state.writeIndex = mod(state.writeIndex, maxStoredSamples) + 1;
        state.sampleCount = min(state.sampleCount + 1, maxStoredSamples);
        state.goodFrames = state.goodFrames + 1;
        expandYAxisForExtrema(sampleValues, sampleValues);

        updateCounters(false);
        if ~state.paused && elapsed - state.lastPlotTime >= plotPeriod
            updatePlots();
            state.lastPlotTime = elapsed;
        end
    end

    function processAckMessage(fields)
        if numel(fields) ~= 3
            registerControlProtocolError('ACK 字段数量无效');
            return;
        end

        variableName = fields(2);
        confirmedValue = str2double(fields(3));
        parameterIndex = findDspParameter(variableName);
        if strlength(variableName) == 0 || isempty(parameterIndex) || ...
                ~isscalar(confirmedValue) || ~isfinite(confirmedValue) || ...
                confirmedValue < dspParameters.minimums(parameterIndex) || ...
                confirmedValue > dspParameters.maximums(parameterIndex)
            registerControlProtocolError('ACK 参数名或返回值无效');
            return;
        end

        state.commandAckCount = state.commandAckCount + 1;
        dspParameters.confirmedValues(parameterIndex) = confirmedValue;
        dspParameters.values(parameterIndex) = confirmedValue;
        dspParameters.statuses(parameterIndex) = "已确认";
        if strcmp(state.pendingVariable, char(variableName))
            clearPendingCommand();
        end
        updateDspParameterControls();
        [saved, ~] = saveDspParameterSettings();
        if saved
            statusLabel.Text = sprintf('DSP 已更新 %s = %.15g', ...
                char(variableName), confirmedValue);
        else
            statusLabel.Text = sprintf( ...
                'DSP 已更新 %s = %.15g，但本地参数配置未保存', ...
                char(variableName), confirmedValue);
        end
    end

    function processErrorMessage(fields)
        if numel(fields) ~= 3 || strlength(fields(2)) == 0 || ...
                strlength(fields(3)) == 0
            registerControlProtocolError('ERR 消息格式无效');
            return;
        end

        variableName = fields(2);
        errorCode = fields(3);
        parameterIndex = findDspParameter(variableName);
        state.commandErrorCount = state.commandErrorCount + 1;
        if ~isempty(parameterIndex)
            dspParameters.statuses(parameterIndex) = "写入失败";
        end
        if strcmp(state.pendingVariable, char(variableName))
            clearPendingCommand();
        end
        updateDspParameterControls();
        statusLabel.Text = sprintf('DSP 拒绝 %s: %s', ...
            char(variableName), char(errorCode));
    end

    function registerControlProtocolError(message)
        state.commandErrorCount = state.commandErrorCount + 1;
        statusLabel.Text = ['控制协议异常: ' message];
    end

    function updatePlots()
        if state.sampleCount == 0 || ~isvalid(fig)
            return;
        end

        visibleEnd = latestSampleTime();
        visibleStart = max(0, visibleEnd - windowField.Value);
        firstLogicalIndex = findFirstVisibleSample(visibleStart);
        visibleCount = state.sampleCount - firstLogicalIndex + 1;

        if visibleCount <= maxPlotSamples
            logicalIndices = firstLogicalIndex:state.sampleCount;
        else
            logicalIndices = round(linspace( ...
                firstLogicalIndex, state.sampleCount, maxPlotSamples));
        end

        physicalIndices = logicalToPhysical(logicalIndices);
        shownTime = state.time(physicalIndices);
        shownValues = state.values(physicalIndices, :);
        for channelIndex = 1:channelSettings.channelCount
            if channelSettings.visible(channelIndex)
                lineHandles(channelIndex).XData = shownTime;
                lineHandles(channelIndex).YData = shownValues(:, channelIndex);
                lineHandles(channelIndex).Visible = 'on';
            else
                lineHandles(channelIndex).XData = NaN;
                lineHandles(channelIndex).YData = NaN;
                lineHandles(channelIndex).Visible = 'off';
            end
        end
        for plotIndex = 1:channelSettings.plotCount
            if visibleEnd > visibleStart
                axesHandles(plotIndex).XLim = [visibleStart visibleEnd];
            end
        end
        drawnow limitrate nocallbacks;
    end

    function updateCounters(forceUpdate)
        if ~isvalid(fig)
            return;
        end

        currentTime = state.timeOffset + toc(state.clock);
        if ~forceUpdate && currentTime - state.lastCounterTime < counterPeriod
            return;
        end

        goodLabel.Text = sprintf('有效帧: %d', state.goodFrames);
        badLabel.Text = sprintf('异常帧: %d', state.badFrames);
        sampleLabel.Text = sprintf('缓存点数: %d', state.sampleCount);
        state.lastCounterTime = currentTime;
    end

    function onPauseToggle(~, ~)
        state.paused = ~state.paused;
        if state.paused
            pauseButton.Text = '继续显示';
            pauseButton.BackgroundColor = warningButtonColor;
            pauseButton.FontColor = textColor;
            statusLabel.Text = '显示已暂停，数据仍在接收';
        else
            pauseButton.Text = '暂停显示';
            pauseButton.BackgroundColor = secondaryButtonColor;
            pauseButton.FontColor = textColor;
            if state.connected
                statusLabel.Text = sprintf('已连接 %s @ %d baud', ...
                    string(portDropDown.Value), round(baudField.Value));
            end
            updatePlots();
        end
    end

    function onResetYAxis(~, ~)
        resetYAxisRanges();
        statusLabel.Text = 'Y 轴已按当前可见数据重置';
    end

    function onClear(~, ~)
        resetAcquisitionData(channelSettings.channelCount);

        for channelIndex = 1:channelSettings.channelCount
            lineHandles(channelIndex).XData = NaN;
            lineHandles(channelIndex).YData = NaN;
        end
        for plotIndex = 1:channelSettings.plotCount
            axesHandles(plotIndex).XLimMode = 'auto';
        end
        resetYAxisRanges();
        updateCounters(true);
        statusLabel.Text = '缓存与统计已清空';
    end

    function resetAcquisitionData(channelCount)
        state.values = zeros(maxStoredSamples, channelCount);
        state.sampleCount = 0;
        state.writeIndex = 1;
        state.goodFrames = 0;
        state.badFrames = 0;
        state.clock = tic;
        state.timeOffset = 0;
        state.lastPlotTime = -inf;
        state.lastCounterTime = -inf;
    end

    function onSave(~, ~)
        if state.sampleCount == 0
            uialert(fig, '当前没有可保存的数据。', '保存 CSV');
            return;
        end

        defaultName = ['SerialData_' datestr(now, 'yyyymmdd_HHMMSS') '.csv']; %#ok<TNOW1,DATST>
        [fileName, folder] = uiputfile('*.csv', '保存采样数据', defaultName);
        if isequal(fileName, 0)
            return;
        end

        [orderedTime, orderedValues] = orderedSamples();
        variableNames = buildCsvVariableNames();
        output = array2table([orderedTime orderedValues], ...
            'VariableNames', variableNames);
        try
            writetable(output, fullfile(folder, fileName));
            statusLabel.Text = sprintf('已保存 %d 个采样点', height(output));
        catch exception
            uialert(fig, exception.message, '保存失败');
        end
    end

    function firstIndex = findFirstVisibleSample(startTime)
        low = 1;
        high = state.sampleCount;
        while low < high
            middle = floor((low + high) / 2);
            physicalIndex = logicalToPhysical(middle);
            if state.time(physicalIndex) < startTime
                low = middle + 1;
            else
                high = middle;
            end
        end
        firstIndex = low;
    end

    function physicalIndices = logicalToPhysical(logicalIndices)
        if state.sampleCount < maxStoredSamples
            oldestIndex = 1;
        else
            oldestIndex = state.writeIndex;
        end
        physicalIndices = mod(oldestIndex + logicalIndices - 2, ...
            maxStoredSamples) + 1;
    end

    function latestTime = latestSampleTime()
        if state.sampleCount == 0
            latestTime = 0;
            return;
        end
        latestIndex = mod(state.writeIndex - 2, maxStoredSamples) + 1;
        latestTime = state.time(latestIndex);
    end

    function [orderedTime, orderedValues] = orderedSamples()
        physicalIndices = logicalToPhysical(1:state.sampleCount);
        orderedTime = state.time(physicalIndices);
        orderedValues = state.values(physicalIndices, :);
    end

    function parameters = defaultDspParameters()
        parameters.names = ["V_REF", "I_REF", "KP_I", "KI_I"];
        parameters.units = ["V", "A", "", ""];
        parameters.minimums = [0, 0, 0, 0];
        parameters.maximums = [100, 20, 10, 10000];
        parameters.values = [75, 4.5, 0.015, 75];
        parameters.confirmedValues = nan(size(parameters.values));
        parameters.statuses = repmat("未发送", size(parameters.names));
    end

    function parameters = loadDspParameters()
        parameters = defaultDspParameters();
        try
            if ~ispref(preferencesGroup, dspParameterPreferencesKey)
                return;
            end
            storedParameters = getpref( ...
                preferencesGroup, dspParameterPreferencesKey);
            [validSettings, ~] = ...
                isValidDspParameterSettings(storedParameters);
            if ~validSettings
                return;
            end

            parameters.names = reshape( ...
                strtrim(string(storedParameters.names)), 1, []);
            parameters.units = reshape( ...
                strtrim(string(storedParameters.units)), 1, []);
            parameters.minimums = reshape( ...
                double(storedParameters.minimums), 1, []);
            parameters.maximums = reshape( ...
                double(storedParameters.maximums), 1, []);
            parameters.values = reshape( ...
                double(storedParameters.values), 1, []);
            parameters.confirmedValues = nan(size(parameters.values));
            parameters.statuses = repmat( ...
                "未发送", size(parameters.names));
        catch
            parameters = defaultDspParameters();
        end
    end

    function [valid, errorMessage] = isValidDspParameterSettings(parameters)
        valid = false;
        errorMessage = '';
        requiredFields = {'names', 'units', 'minimums', ...
            'maximums', 'values'};
        if ~isstruct(parameters) || ...
                ~all(isfield(parameters, requiredFields))
            errorMessage = '参数配置缺少必要字段。';
            return;
        end

        try
            names = reshape(strtrim(string(parameters.names)), 1, []);
            units = reshape(strtrim(string(parameters.units)), 1, []);
            minimums = reshape(double(parameters.minimums), 1, []);
            maximums = reshape(double(parameters.maximums), 1, []);
            values = reshape(double(parameters.values), 1, []);
        catch
            errorMessage = '参数配置包含无法转换的数据。';
            return;
        end

        parameterCount = numel(names);
        if parameterCount < 1 || parameterCount > maxDspParameterCount
            errorMessage = sprintf('DSP 参数数量必须在 1 到 %d 之间。', ...
                maxDspParameterCount);
            return;
        end
        if numel(units) ~= parameterCount || ...
                numel(minimums) ~= parameterCount || ...
                numel(maximums) ~= parameterCount || ...
                numel(values) ~= parameterCount
            errorMessage = '参数配置各字段的数量不一致。';
            return;
        end

        validName = cellfun(@(name) ~isempty(regexp(name, ...
            '^[A-Za-z_][A-Za-z0-9_]{0,31}$', 'once')), cellstr(names));
        if any(~validName)
            errorMessage = ['参数名称必须是 1～32 个字符的标识符，' ...
                '只能包含字母、数字和下划线，且首字符不能是数字。'];
            return;
        end
        if numel(unique(lower(names))) ~= parameterCount
            errorMessage = '参数名称不能重复，大小写不同也视为重复。';
            return;
        end
        if any(strlength(units) > 16) || ...
                any(contains(units, newline)) || ...
                any(contains(units, char(13)))
            errorMessage = '单位不能包含换行，且长度不能超过 16 个字符。';
            return;
        end
        if any(~isfinite(minimums)) || any(~isfinite(maximums)) || ...
                any(~isfinite(values))
            errorMessage = '当前值、最小值和最大值必须是有限数值。';
            return;
        end
        if any(minimums >= maximums)
            errorMessage = '每个参数的最小值必须小于最大值。';
            return;
        end
        if any(values < minimums | values > maximums)
            errorMessage = '当前设定值必须位于对应的最小值和最大值之间。';
            return;
        end
        valid = true;
    end

    function value = numericDspParameterValue(inputValue)
        if isnumeric(inputValue) && isscalar(inputValue)
            value = double(inputValue);
        elseif ischar(inputValue) || isstring(inputValue)
            value = str2double(string(inputValue));
        else
            value = NaN;
        end
    end

    function [saved, errorMessage] = saveDspParameterSettings()
        storedParameters.names = cellstr(dspParameters.names);
        storedParameters.units = cellstr(dspParameters.units);
        storedParameters.minimums = dspParameters.minimums;
        storedParameters.maximums = dspParameters.maximums;
        storedParameters.values = dspParameters.values;
        saved = false;
        errorMessage = '';
        try
            setpref(preferencesGroup, dspParameterPreferencesKey, ...
                storedParameters);
            saved = true;
        catch exception
            errorMessage = exception.message;
        end
    end

    function saveDspParameterSettingsWithAlert()
        [saved, errorMessage] = saveDspParameterSettings();
        if ~saved && ~isempty(state.dspParameterFigure) && ...
                isvalid(state.dspParameterFigure)
            uialert(state.dspParameterFigure, ...
                ['参数修改已在本次运行中生效，但无法保存到 MATLAB 首选项。' ...
                newline errorMessage], '保存参数失败');
        end
    end

    function settings = defaultChannelSettings()
        settings.names = defaultChannelNames;
        settings.units = defaultChannelUnits;
        settings.visible = defaultChannelVisible;
        settings.plotIndex = defaultPlotIndex;
        settings.expandY = defaultYAxisExpand;
        settings.yLimits = defaultYLimits;
        settings.plotCount = defaultPlotCount;
        settings.channelCount = defaultChannelCount;
        settings.colors = zeros(maxChannelCount, 3);
        settings.colorIsCustom = false(1, maxChannelCount);
        settings = assignAutomaticColors(settings);
    end

    function settings = loadChannelSettings()
        settings = defaultChannelSettings();
        try
            if ispref(preferencesGroup, preferencesKey)
                storedSettings = getpref(preferencesGroup, preferencesKey);
            elseif ispref(legacyPreferencesGroup, preferencesKey)
                storedSettings = getpref(legacyPreferencesGroup, preferencesKey);
            else
                return;
            end

            if ~isfield(storedSettings, 'expandY') && ...
                    isfield(storedSettings, 'autoY')
                storedSettings.expandY = storedSettings.autoY;
            end
            storedSettings = completeStoredSettings(storedSettings);
            if ~isValidChannelSettings(storedSettings)
                return;
            end

            settings.names = reshape(strtrim(string(storedSettings.names)), ...
                1, maxChannelCount);
            settings.units = reshape(strtrim(string(storedSettings.units)), ...
                1, maxChannelCount);
            settings.visible = reshape(logical(storedSettings.visible), ...
                1, maxChannelCount);
            settings.plotIndex = reshape(double(storedSettings.plotIndex), ...
                1, maxChannelCount);
            settings.expandY = reshape(logical(storedSettings.expandY), ...
                1, maxChannelCount);
            settings.yLimits = double(storedSettings.yLimits);
            settings.plotCount = double(storedSettings.plotCount);
            settings.channelCount = double(storedSettings.channelCount);
            settings.colors = double(storedSettings.colors);
            settings.colorIsCustom = reshape( ...
                logical(storedSettings.colorIsCustom), 1, maxChannelCount);
            settings = assignAutomaticColors(settings);
        catch
            settings = defaultChannelSettings();
        end
    end

    function settings = completeStoredSettings(storedSettings)
        settings = defaultChannelSettings();
        if ~isstruct(storedSettings)
            return;
        end

        if isfield(storedSettings, 'plotCount')
            settings.plotCount = storedSettings.plotCount;
        end
        if isfield(storedSettings, 'channelCount')
            settings.channelCount = storedSettings.channelCount;
        end

        vectorFields = {'names', 'units', 'visible', 'plotIndex', 'expandY'};
        for fieldIndex = 1:numel(vectorFields)
            fieldName = vectorFields{fieldIndex};
            if ~isfield(storedSettings, fieldName)
                continue;
            end
            switch fieldName
                case {'names', 'units'}
                    storedValues = reshape( ...
                        string(storedSettings.(fieldName)), 1, []);
                case {'visible', 'expandY'}
                    storedValues = reshape( ...
                        logical(storedSettings.(fieldName)), 1, []);
                otherwise
                    storedValues = reshape( ...
                        double(storedSettings.(fieldName)), 1, []);
            end
            copyCount = min(numel(storedValues), maxChannelCount);
            settings.(fieldName)(1:copyCount) = storedValues(1:copyCount);
        end
        if isfield(storedSettings, 'yLimits')
            storedYLimits = double(storedSettings.yLimits);
            if size(storedYLimits, 2) == 2
                copyCount = min(size(storedYLimits, 1), maxChannelCount);
                settings.yLimits(1:copyCount, :) = ...
                    storedYLimits(1:copyCount, :);
            end
        end
        if isfield(storedSettings, 'colors') && ...
                isfield(storedSettings, 'colorIsCustom')
            storedColors = double(storedSettings.colors);
            storedCustomFlags = double(storedSettings.colorIsCustom);
            validColors = size(storedColors, 2) == 3 && ...
                size(storedColors, 1) <= maxChannelCount && ...
                all(isfinite(storedColors), 'all') && ...
                all(storedColors >= 0, 'all') && ...
                all(storedColors <= 1, 'all');
            validCustomFlags = numel(storedCustomFlags) <= maxChannelCount && ...
                all(isfinite(storedCustomFlags)) && ...
                all(storedCustomFlags == 0 | storedCustomFlags == 1);
            if validColors && validCustomFlags
                colorCount = size(storedColors, 1);
                flagCount = numel(storedCustomFlags);
                settings.colors(1:colorCount, :) = storedColors;
                settings.colorIsCustom(1:flagCount) = ...
                    logical(reshape(storedCustomFlags, 1, []));
            end
        end

        plotCount = double(settings.plotCount);
        if isscalar(plotCount) && isfinite(plotCount) && ...
                plotCount == round(plotCount) && plotCount >= 1 && plotCount <= 4
            settings.plotIndex = min(double(settings.plotIndex), plotCount);
        end
        settings = assignAutomaticColors(settings);
    end

    function valid = isValidChannelSettings(settings)
        requiredFields = {'names', 'units', 'visible', 'plotIndex', ...
            'expandY', 'yLimits', 'plotCount', 'channelCount', ...
            'colors', 'colorIsCustom'};
        valid = isstruct(settings) && all(isfield(settings, requiredFields));
        if ~valid
            return;
        end

        try
            names = strtrim(string(settings.names));
            units = string(settings.units);
            visible = double(settings.visible);
            plotIndex = double(settings.plotIndex);
            expandY = double(settings.expandY);
            yLimits = double(settings.yLimits);
            plotCount = double(settings.plotCount);
            channelCount = double(settings.channelCount);
            colors = double(settings.colors);
            colorIsCustom = double(settings.colorIsCustom);
            valid = numel(names) == maxChannelCount && ...
                numel(units) == maxChannelCount && ...
                numel(visible) == maxChannelCount && all(isfinite(visible)) && ...
                all(visible == 0 | visible == 1) && ...
                numel(plotIndex) == maxChannelCount && ...
                all(isfinite(plotIndex)) && ...
                all(plotIndex == round(plotIndex)) && all(plotIndex >= 1) && ...
                isscalar(plotCount) && isfinite(plotCount) && ...
                plotCount == round(plotCount) && plotCount >= 1 && ...
                plotCount <= 4 && all(plotIndex <= plotCount) && ...
                isscalar(channelCount) && isfinite(channelCount) && ...
                channelCount == round(channelCount) && channelCount >= 1 && ...
                channelCount <= maxChannelCount && ...
                numel(expandY) == maxChannelCount && ...
                all(isfinite(expandY)) && ...
                all(expandY == 0 | expandY == 1) && ...
                isequal(size(yLimits), [maxChannelCount 2]) && ...
                all(isfinite(yLimits), 'all') && ...
                all(yLimits(:, 1) < yLimits(:, 2)) && ...
                isequal(size(colors), [maxChannelCount 3]) && ...
                all(isfinite(colors), 'all') && ...
                all(colors >= 0, 'all') && all(colors <= 1, 'all') && ...
                numel(colorIsCustom) == maxChannelCount && ...
                all(isfinite(colorIsCustom)) && ...
                all(colorIsCustom == 0 | colorIsCustom == 1) && ...
                all(strlength(names) > 0);
        catch
            valid = false;
        end
    end

    function data = channelSettingsToTableData(settings)
        data = cell(maxChannelCount, 8);
        for index = 1:maxChannelCount
            data{index, 1} = char(settings.names(index));
            data{index, 2} = char(settings.units(index));
            data{index, 3} = logical(settings.visible(index));
            data{index, 4} = settings.plotIndex(index);
            data{index, 5} = colorToHex(settings.colors(index, :));
            data{index, 6} = logical(settings.expandY(index));
            data{index, 7} = settings.yLimits(index, 1);
            data{index, 8} = settings.yLimits(index, 2);
        end
    end

    function settings = assignAutomaticColors(settings)
        for plotIndex = 1:settings.plotCount
            channelIndices = find(settings.plotIndex == plotIndex);
            customIndices = channelIndices( ...
                settings.colorIsCustom(channelIndices));
            automaticIndices = channelIndices( ...
                ~settings.colorIsCustom(channelIndices));
            assignedColors = settings.colors(customIndices, :);
            availableColors = defaultColorPalette;

            for channelIndex = automaticIndices
                if isempty(assignedColors)
                    selectedIndex = 1;
                else
                    minimumDistances = inf(size(availableColors, 1), 1);
                    for colorIndex = 1:size(availableColors, 1)
                        differences = assignedColors - ...
                            availableColors(colorIndex, :);
                        minimumDistances(colorIndex) = min(sqrt( ...
                            sum(differences .^ 2, 2)));
                    end
                    [~, selectedIndex] = max(minimumDistances);
                end

                selectedColor = availableColors(selectedIndex, :);
                settings.colors(channelIndex, :) = selectedColor;
                assignedColors(end + 1, :) = selectedColor; %#ok<AGROW>
                availableColors(selectedIndex, :) = [];
            end
        end
    end

    function hexText = colorToHex(color)
        colorBytes = round(255 * min(max(double(color), 0), 1));
        hexText = sprintf('#%02X%02X%02X', colorBytes(1), ...
            colorBytes(2), colorBytes(3));
    end

    function updateColorButton(color)
        if isempty(state.settingsColorButton) || ...
                ~isvalid(state.settingsColorButton)
            return;
        end
        state.settingsColorButton.BackgroundColor = color;
        luminance = 0.2126 * color(1) + 0.7152 * color(2) + ...
            0.0722 * color(3);
        if luminance < 0.5
            state.settingsColorButton.FontColor = [1 1 1];
        else
            state.settingsColorButton.FontColor = textColor;
        end
    end

    function rowNames = channelRowNames(channelCount)
        rowNames = arrayfun(@(index) sprintf('Channel %d', index), ...
            1:channelCount, 'UniformOutput', false);
    end

    function [saved, errorMessage] = saveChannelSettings()
        storedSettings = channelSettings;
        storedSettings.names = cellstr(channelSettings.names);
        storedSettings.units = cellstr(channelSettings.units);
        saved = false;
        errorMessage = '';
        try
            setpref(preferencesGroup, preferencesKey, storedSettings);
            saved = true;
        catch exception
            errorMessage = exception.message;
        end
    end

    function resetYAxisRanges()
        state.currentYLimits = plotBaseYLimits();
        updateYAxisLimits();
        if state.sampleCount == 0
            return;
        end

        visibleEnd = latestSampleTime();
        visibleStart = max(0, visibleEnd - windowField.Value);
        firstLogicalIndex = findFirstVisibleSample(visibleStart);
        logicalIndices = firstLogicalIndex:state.sampleCount;
        physicalIndices = logicalToPhysical(logicalIndices);
        visibleValues = state.values(physicalIndices, :);
        expandYAxisForExtrema(min(visibleValues, [], 1), ...
            max(visibleValues, [], 1));
    end

    function expandYAxisForExtrema(minimums, maximums)
        limitsChanged = false;
        baseLimits = plotBaseYLimits();
        activeChannels = 1:channelSettings.channelCount;
        for plotIndex = 1:channelSettings.plotCount
            channelIndices = activeChannels( ...
                channelSettings.visible(activeChannels) & ...
                channelSettings.plotIndex(activeChannels) == plotIndex & ...
                channelSettings.expandY(activeChannels));
            margin = yExpansionMargin * diff(baseLimits(plotIndex, :));
            for channelIndex = channelIndices
                if minimums(channelIndex) < state.currentYLimits(plotIndex, 1)
                    state.currentYLimits(plotIndex, 1) = ...
                        minimums(channelIndex) - margin;
                    limitsChanged = true;
                end
                if maximums(channelIndex) > state.currentYLimits(plotIndex, 2)
                    state.currentYLimits(plotIndex, 2) = ...
                        maximums(channelIndex) + margin;
                    limitsChanged = true;
                end
            end
        end

        if limitsChanged
            updateYAxisLimits();
        end
    end

    function limits = plotBaseYLimits()
        limits = repmat([0 1], channelSettings.plotCount, 1);
        activeChannels = 1:channelSettings.channelCount;
        for plotIndex = 1:channelSettings.plotCount
            channelIndices = activeChannels( ...
                channelSettings.visible(activeChannels) & ...
                channelSettings.plotIndex(activeChannels) == plotIndex);
            if isempty(channelIndices)
                continue;
            end
            limits(plotIndex, 1) = min(channelSettings.yLimits(channelIndices, 1));
            limits(plotIndex, 2) = max(channelSettings.yLimits(channelIndices, 2));
        end
    end

    function updateYAxisLimits()
        for plotIndex = 1:channelSettings.plotCount
            axesHandles(plotIndex).YLim = state.currentYLimits(plotIndex, :);
        end
    end

    function variableNames = buildCsvVariableNames()
        channelCount = channelSettings.channelCount;
        channelVariableNames = channelNames(1:channelCount);
        for index = 1:channelCount
            if strlength(channelUnits(index)) > 0
                channelVariableNames(index) = channelNames(index) + ...
                    "_" + channelUnits(index);
            end
        end

        channelVariableNames = matlab.lang.makeValidName( ...
            cellstr(channelVariableNames), 'ReplacementStyle', 'underscore');
        channelVariableNames = matlab.lang.makeUniqueStrings( ...
            channelVariableNames, {'Time_s'});
        variableNames = [{'Time_s'}, channelVariableNames];
    end

    function fontName = selectAvailableFont(preferredFont, fallbackFonts)
        candidates = [string(preferredFont), string(fallbackFonts)];
        fontName = char(candidates(1));
        try
            installedFonts = string(listfonts);
            for fontIndex = 1:numel(candidates)
                if any(strcmpi(installedFonts, candidates(fontIndex)))
                    fontName = char(candidates(fontIndex));
                    return;
                end
            end
            if ~isempty(installedFonts)
                fontName = char(installedFonts(1));
            end
        catch
            % Let MATLAB perform its normal font substitution if font
            % enumeration is unavailable on the current platform.
        end
    end

    function disconnectSerial(message)
        if ~isempty(state.serial)
            try
                configureCallback(state.serial, "off");
            catch
            end
        end
        state.serial = [];
        state.connected = false;
        state.paused = false;
        clearPendingCommand();
        dspParameters.confirmedValues(:) = NaN;
        dspParameters.statuses(:) = "未发送";

        if isvalid(fig)
            connectButton.Text = '连接';
            connectButton.Enable = 'on';
            connectButton.BackgroundColor = primaryButtonColor;
            refreshButton.Enable = 'on';
            portDropDown.Enable = 'on';
            baudField.Enable = 'on';
            pauseButton.Text = '暂停显示';
            pauseButton.Enable = 'off';
            pauseButton.BackgroundColor = secondaryButtonColor;
            pauseButton.FontColor = textColor;
            statusLamp.Color = [0.65 0.65 0.65];
            statusLabel.Text = message;
            updateDspParameterControls();
        end
    end

    function onClose(~, ~)
        state.closing = true;
        closeChannelSettings();
        closeDspParameterSettings();
        disconnectSerial('正在关闭');
        delete(fig);
    end
end

function restoreMonitorWindowStack(mainFigure, settingsFigure)
drawnow;
if ~isempty(mainFigure) && isvalid(mainFigure)
    figure(mainFigure);
end
if ~isempty(settingsFigure) && isvalid(settingsFigure)
    figure(settingsFigure);
end
drawnow;
end
