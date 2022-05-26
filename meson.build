project('omni-plotter', ['vala', 'c'], version: '0.1.0')

vapi_dir = join_paths(meson.current_source_dir(), 'vapi')
add_project_arguments(['--vapidir', vapi_dir], language: 'vala')
gnome = import('gnome')

cc = meson.get_compiler('c')
m_dep = cc.find_library('m')

dependencies = [
	dependency('gee-0.8'),
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gtk+-3.0'),
	dependency('libxml-2.0'),
	dependency('msgpack'),
	dependency('livechart'),
	m_dep
]

sources = files(
	'src/main.vala',
	'src/protocol/ProtocolReceiver.vala',
	'src/protocol/MpTimelineReceiver.vala',
	'src/protocol/PacketRecorder.vala',
	'src/protocol/calculation/Calculator.vala',
	'src/protocol/calculation/Abs.vala',
	'src/protocol/calculation/Atan2.vala',
	'src/protocol/calculation/Diff.vala',
	'src/protocol/calculation/Sum.vala',
	'src/protocol/calculation/ToInt.vala',
	'src/myapp/ChartGridBox.vala',
	'src/myapp/MainApp.vala',
	'src/myapp/PlotToggler.vala',
	'src/context/RecordStorage.vala',
	'src/utils/RGBAUtils.vala',
	'src/utils/XmlUtils.vala',
)

gresource = gnome.compile_resources(
	'gresource',
	'resource' / 'gresource.xml',
	source_dir: 'resource'
)

executable(
	'omni-plotter', 
	gresource, 
	sources, 
	dependencies: dependencies
)
