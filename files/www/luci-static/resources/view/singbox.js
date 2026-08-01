'use strict';
'require view';
'require fs';
'require ui';
'require rpc';

// 服务状态查询(返回所有服务,再取 sing-box)
const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

return view.extend({
	SB_INIT: '/etc/init.d/sing-box',
	SB_CONF: '/etc/sing-box/config.json',
	SB_LOG: '/var/log/sing-box.log',

	load() {
		return Promise.all([
			L.resolveDefault(callServiceList('sing-box'), {}),
			L.resolveDefault(fs.read_direct(this.SB_CONF), ''),
			L.resolveDefault(fs.exec('/bin/cat', [this.SB_LOG]), {})
		]).then(([status, conf, log]) => {
			return { status: status, conf: conf, log: log };
		});
	},

	isRunning(status) {
		try {
			const inst = (status['sing-box'] && status['sing-box'].instances) || {};
			return Object.keys(inst).length > 0;
		} catch (e) {
			return false;
		}
	},

	act(cmd) {
		return fs.exec(this.SB_INIT, [cmd]).then(res => {
			window.setTimeout(() => this.renderStatus(), 1500);
			return res;
		}).catch(err => {
			ui.addNotification(null, E('p', _('执行失败: ') + err.message));
		});
	},

	renderStatus() {
		const statusEl = document.getElementById('sb-status');
		if (!statusEl) return;
		callServiceList('sing-box').then(s => {
			const running = this.isRunning(s);
			statusEl.innerHTML = running
				? '<span style="color:green;font-weight:bold">● 运行中</span>'
				: '<span style="color:red;font-weight:bold">● 已停止</span>';
		}).catch(() => {
			statusEl.innerHTML = '<span style="color:gray">状态未知</span>';
		});
	},

	render(data) {
		const running = this.isRunning(data.status);

		const viewEl = E('div', { class: 'cbi-map' });
		viewEl.appendChild(E('h2', { name: 'content' }, _('sing-box 服务端')));

		// 状态与控制区
		const section = E('fieldset', { class: 'cbi-section' });
		section.appendChild(E('legend', _('状态与控制')));

		const statusRow = E('div', { class: 'cbi-value' });
		statusRow.appendChild(E('label', { class: 'cbi-value-title' }, _('服务状态')));
		const statusBox = E('div', { class: 'cbi-value-field', id: 'sb-status' });
		statusBox.innerHTML = running
			? '<span style="color:green;font-weight:bold">● 运行中</span>'
			: '<span style="color:red;font-weight:bold">● 已停止</span>';
		statusRow.appendChild(statusBox);
		section.appendChild(statusRow);

		// 按钮行
		const btnRow = E('div', { class: 'cbi-value' });
		btnRow.appendChild(E('label', { class: 'cbi-value-title' }, _('操作')));
		const btnBox = E('div', { class: 'cbi-value-field' });

		const btnStart = E('button', { class: 'cbi-button cbi-button-apply', type: 'button' }, _('启动'));
		btnStart.onclick = () => { ui.showModal(_('正在启动…')); this.act('start').then(() => ui.hideModal()); };
		btnBox.appendChild(btnStart);
		btnBox.appendChild(document.createTextNode(' '));

		const btnStop = E('button', { class: 'cbi-button cbi-button-reset', type: 'button' }, _('停止'));
		btnStop.onclick = () => { ui.showModal(_('正在停止…')); this.act('stop').then(() => ui.hideModal()); };
		btnBox.appendChild(btnStop);
		btnBox.appendChild(document.createTextNode(' '));

		const btnRestart = E('button', { class: 'cbi-button cbi-button-apply', type: 'button' }, _('重启'));
		btnRestart.onclick = () => { ui.showModal(_('正在重启…')); this.act('restart').then(() => ui.hideModal()); };
		btnBox.appendChild(btnRestart);

		btnRow.appendChild(btnBox);
		section.appendChild(btnRow);
		viewEl.appendChild(section);

		// 配置编辑区
		const confSection = E('fieldset', { class: 'cbi-section' });
		confSection.appendChild(E('legend', _('配置文件 (config.json)')));
		confSection.appendChild(E('p', { class: 'cbi-section-descr' },
			_('编辑 vmess+ws / http / socks 的 inbound 配置。修改后点击保存,再点上方重启生效。')));

		const ta = E('textarea', {
			class: 'cbi-input-textarea',
			style: 'width:100%;height:360px;font-family:monospace;font-size:13px',
			wrap: 'off',
			spellcheck: 'false'
		}, data.conf ?? '');

		const saveBtn = E('button', { class: 'cbi-button cbi-button-save', type: 'button', style: 'margin-top:8px' }, _('保存配置'));
		saveBtn.onclick = () => {
			ui.showModal(_('正在保存…'));
			fs.write(this.SB_CONF, ta.value).then(() => {
				ui.hideModal();
				ui.addNotification(null, E('p', _('配置已保存,请点击「重启」使配置生效。')));
			}).catch(err => {
				ui.hideModal();
				ui.addNotification(null, E('p', _('保存失败: ') + err.message));
			});
		};
		confSection.appendChild(ta);
		confSection.appendChild(E('div', {}, saveBtn));
		viewEl.appendChild(confSection);

		// 日志区
		const logSection = E('fieldset', { class: 'cbi-section' });
		logSection.appendChild(E('legend', _('运行日志')));
		logSection.appendChild(E('p', { class: 'cbi-section-descr' },
			_('日志写入 /var/log/sing-box.log(tmpfs,重启清空)。logrotate 每天轮转保留 3 份,超 1MB 也轮转。')));
		const logText = (data.log && (data.log.stdout || data.log.stderr)) || _('暂无日志');
		const logBox = E('pre', {
			style: 'width:100%;height:240px;overflow:auto;background:#1e1e1e;color:#d4d4d4;padding:10px;font-family:monospace;font-size:12px;border-radius:4px;white-space:pre-wrap;'
		}, logText);
		logSection.appendChild(logBox);

		const refreshBtn = E('button', { class: 'cbi-button', type: 'button', style: 'margin-top:8px' }, _('刷新日志'));
		refreshBtn.onclick = () => {
			fs.exec('/bin/cat', [this.SB_LOG]).then(res => {
				logBox.textContent = (res && (res.stdout || res.stderr)) || _('暂无日志');
			}).catch(() => {
				logBox.textContent = _('读取日志失败');
			});
		};

		const clearBtn = E('button', { class: 'cbi-button cbi-button-reset', type: 'button', style: 'margin-top:8px;margin-left:8px' }, _('清空日志'));
		clearBtn.onclick = () => {
			if (!confirm(_('确认清空 sing-box 日志?'))) return;
			fs.exec('/usr/bin/truncate', ['-s', '0', this.SB_LOG]).then(() => {
				logBox.textContent = _('日志已清空');
			}).catch(() => {
				ui.addNotification(null, E('p', _('清空失败')));
			});
		};
		logSection.appendChild(E('div', {}, [refreshBtn, clearBtn]));
		viewEl.appendChild(logSection);

		return viewEl;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
