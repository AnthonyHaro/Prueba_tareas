import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

class TareasPage extends StatefulWidget {
  const TareasPage({super.key});

  @override
  State<TareasPage> createState() => _TareasPageState();
}

class _TareasPageState extends State<TareasPage> {
  final supabase = Supabase.instance.client;
  List<dynamic> misTareas = [];
  List<dynamic> otrasTareas = [];

  @override
  void initState() {
    super.initState();
    obtenerTareas();
  }

  Future<void> obtenerTareas() async {
    final userId = supabase.auth.currentUser?.id;
    final response = await supabase.from('tareas').select().order('fecha', ascending: false);

    setState(() {
      misTareas = response.where((t) => t['user_id'] == userId).toList();
      otrasTareas = response.where((t) => t['user_id'] != userId).toList();
    });
  }

  Future<void> cambiarEstado(int id, bool nuevoEstado) async {
    await supabase.from('tareas').update({'estado': nuevoEstado}).eq('id', id);
    obtenerTareas();
  }

  Future<void> cerrarSesion() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  Widget tareaItem(Map<String, dynamic> tarea, {required bool editable}) {
    final estadoTexto = tarea['estado'] == true ? '✅ Completada' : '🕓 Pendiente';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      shadowColor: Colors.grey.withOpacity(0.3),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        title: Text(
          tarea['titulo'],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text("Fecha: ${tarea['fecha'].toString().split('T').first}"),
            Text("Estado: $estadoTexto", style: TextStyle(color: tarea['estado'] ? Colors.green[700] : Colors.orange[700])),
            if (tarea['imagen_url'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    tarea['imagen_url'],
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator(value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null)),
                      );
                    },
                    errorBuilder: (_, __, ___) => const SizedBox(height: 140, child: Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey))),
                  ),
                ),
              ),
          ],
        ),
        trailing: Checkbox(
          value: tarea['estado'],
          activeColor: Colors.green,
          onChanged: editable ? (val) => cambiarEstado(tarea['id'], val!) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Tareas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: cerrarSesion,
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: obtenerTareas,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text("Mis tareas", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            ...misTareas.map((t) => tareaItem(t, editable: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text("Tareas de otros usuarios", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            ...otrasTareas.map((t) => tareaItem(t, editable: false)),
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CrearTareaPage()),
          );
          obtenerTareas();
        },
        label: const Text('Agregar Tarea'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class CrearTareaPage extends StatefulWidget {
  const CrearTareaPage({super.key});

  @override
  State<CrearTareaPage> createState() => _CrearTareaPageState();
}

class _CrearTareaPageState extends State<CrearTareaPage> {
  final supabase = Supabase.instance.client;
  final tituloController = TextEditingController();
  bool estado = false;
  DateTime fecha = DateTime.now();
  Uint8List? imagenBytes;
  String? imagenNombre;

  Future<void> seleccionarDesdeGaleria() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        imagenBytes = result.files.single.bytes;
        imagenNombre = result.files.single.name;
      });
    }
  }

  Future<void> tomarFoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        imagenBytes = bytes;
        imagenNombre = image.name;
      });
    }
  }

  Future<String?> subirImagen() async {
    if (imagenBytes == null || imagenNombre == null) return null;

    final userId = supabase.auth.currentUser?.id;
    final extension = path.extension(imagenNombre!);
    final nombreArchivo = "${userId}_${const Uuid().v4()}$extension";

    final response = await supabase.storage
        .from('imagenestareas')
        .uploadBinary(nombreArchivo, imagenBytes!, fileOptions: const FileOptions(upsert: true));

    if (response.isNotEmpty) {
      return supabase.storage.from('imagenestareas').getPublicUrl(nombreArchivo);
    }
    return null;
  }

  Future<void> guardarTarea() async {
    final userId = supabase.auth.currentUser?.id;
    String? imagenUrl;

    if (imagenBytes != null) {
      imagenUrl = await subirImagen();
    }

    await supabase.from('tareas').insert({
      'titulo': tituloController.text,
      'estado': estado,
      'user_id': userId,
      'fecha': fecha.toIso8601String(),
      'imagen_url': imagenUrl,
    });

    if (mounted) Navigator.pop(context);
  }

  Future<void> _seleccionarFecha(BuildContext context) async {
    final nuevaFecha = await showDatePicker(
      context: context,
      initialDate: fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(backgroundColor: Colors.deepPurple),
            ),
          ),
          child: child!,
        );
      },
    );
    if (nuevaFecha != null) {
      setState(() {
        fecha = nuevaFecha;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text('Nueva Tarea')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: tituloController,
              decoration: InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text("Estado:", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Text(
                  estado ? "✅ Completada" : "🕓 Pendiente",
                  style: TextStyle(
                    color: estado ? Colors.green[700] : Colors.orange[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Checkbox(
                  value: estado,
                  activeColor: Colors.green,
                  onChanged: (val) => setState(() => estado = val!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _seleccionarFecha(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Fecha: ${fecha.toLocal()}'.split(' ')[0]),
            ),
            const SizedBox(height: 20),
            if (imagenBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(imagenBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: tomarFoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: seleccionarDesdeGaleria,
                  icon: const Icon(Icons.image),
                  label: const Text('Galería'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: guardarTarea,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  "Guardar Tarea",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
