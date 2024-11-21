import bpy
import csv

def create_box_from_vertices(vertices, name, is_visible):

    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.from_pydata(vertices, [], [(0, 1, 2, 3)]) 
    mesh.update()

    if is_visible:
        obj.data.materials.append(create_material("VisibleMaterial", (0, 1, 0, 1)))  # Green
    else:
        obj.data.materials.append(create_material("NotVisibleMaterial", (1, 0, 0, 1)))  # Red

def add_viewer(position):
    bpy.ops.mesh.primitive_uv_sphere_add(location=position, radius=0.1)
    viewer = bpy.context.object
    viewer.name = "Viewer"
    viewer.data.materials.append(create_material("ViewerMaterial", (0, 0, 1, 1)))  # Blue color

def create_material(name, color):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    return material

def import_csv(filepath):

    viewer_added = False  # Track if the viewer has been added
    with open(filepath, 'r') as file:
        reader = csv.DictReader(file)
        for row in reader:
            # Parse box face vertices
            vertices = [
                (float(row['x1']), float(row['y1']), float(row['z1'])),
                (float(row['x2']), float(row['y2']), float(row['z2'])),
                (float(row['x3']), float(row['y3']), float(row['z3'])),
                (float(row['x4']), float(row['y4']), float(row['z4']))
            ]
            name = f"Box_{row['box_id']}_{row['face']}"
            is_visible = row['visible'].lower() == 'true'

            create_box_from_vertices(vertices, name, is_visible)
            
            # Add viewer position (only once)
            if not viewer_added:
                viewer_position = (float(row['viewer_x']), float(row['viewer_y']), float(row['viewer_z']))
                add_viewer(viewer_position)
                viewer_added = True

# Filepath to the CSV file
csv_filepath = "C:/Users/Ingrid/Desktop/Result_157.csv"

import_csv(csv_filepath)
