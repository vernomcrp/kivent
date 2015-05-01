# cython: profile=True
from cpython cimport bool
from kivy.properties import (BooleanProperty, StringProperty, NumericProperty,
    ListProperty)
from kivy.graphics import RenderContext, Callback
from kivent_core.rendering.vertex_formats cimport VertexFormat4F, VertexFormat7F
from kivent_core.rendering.vertex_formats import (vertex_format_4f, 
    vertex_format_7f)
from kivent_core.rendering.vertex_format cimport KEVertexFormat
from kivent_core.rendering.cmesh cimport CMesh
from kivent_core.rendering.batching cimport BatchManager, IndexedBatch
from kivent_core.managers.resource_managers import (model_manager, 
    texture_manager)
from kivent_core.managers.resource_managers cimport ModelManager, TextureManager
from kivy.graphics.opengl import (glEnable, glBlendFunc, GL_SRC_ALPHA, GL_ONE, 
    GL_ZERO, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR, GL_ONE_MINUS_SRC_ALPHA, 
    GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR,
    glDisable)
cimport cython
from kivy.graphics.c_opengl cimport GLfloat, GLushort
from staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivent_core.systems.scale_systems cimport ScaleStruct2D
from kivent_core.systems.color_systems cimport ColorStruct
from kivent_core.entity cimport Entity
from kivent_core.rendering.vertmesh cimport VertMesh
from kivy.factory import Factory
from libc.math cimport fabs
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.membuffer cimport Buffer
from kivent_core.systems.staticmemgamesystem cimport ComponentPointerAggregator
from kivent_core.memory_handlers.block cimport MemoryBlock
from kivy.properties import ObjectProperty, NumericProperty


cdef class RenderComponent(MemComponent):
    '''The component associated with various renderers including: Renderer 
    and PhysicsRenderer. Designed for 2d sprites, but potentially useful for 
    other types of models as well. If not using for sprites, ignore **width**,
    **height**, and **texture_key** properties as they are designed for 
    convenience when working with textured quads. Prefer instead to modify the 
    properties of the **vert_mesh** directly.

    **Attributes:**

        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is 
        unattached.

        **width** (float): The width of the sprite.

        **height** (float): The height of the sprite.

        **batch_id** (unsigned int): The batch the entity is assigned to. Read
        Only. If the entity is not currently batched will be <unsigned int>-1.

        **attribute_count** (unsigned int): The number of attributes in the 
        vertex format for the model.

        **texture_key** (str): The name of the texture for this sprite.

        **render** (bool): Whether or not this entity should actually be 
        rendered.

        **vertex_count** (unsigned int): The number of vertices in the current 
        model (the **vert_mesh**). You should not modify the number of vertices 
        while an entity is batched.

        **index_count** (unsigned int): The number of indices in the current 
        model (the **vert_mesh**). You should not modify the number of indices
        while an entity is batched.

        **vert_mesh** (VertMesh): The actual VertMesh object containing the 
        model information for this component. 
    '''

    property entity_id:
        def __get__(self):
            cdef RenderStruct* data = <RenderStruct*>self.pointer
            return data.entity_id

    property width:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            return fabs(vert_mesh[0][0]*2.)

        def __set__(self, float value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            cdef float w
            if value != 0:
                w = .5*value
                set_vertex_attribute = vert_mesh.set_vertex_attribute
                set_vertex_attribute(0,0,-w)
                set_vertex_attribute(1,0,-w)
                set_vertex_attribute(2,0,w)
                set_vertex_attribute(3,0,w)
        

    property height:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            return fabs(vert_mesh[0][1]*2.)

        def __set__(self, float value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            cdef float h
            if value != 0:
                h = .5*value
                set_vertex_attribute = vert_mesh.set_vertex_attribute
                set_vertex_attribute(0,1,-h)
                set_vertex_attribute(1,1,h)
                set_vertex_attribute(2,1,h)
                set_vertex_attribute(3,1,-h)


    property batch_id:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            return component_data.batch_id


    property attribute_count:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            return component_data.attrib_count

        def __set__(self, int value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            component_data.attrib_count = value
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            vert_mesh.attribute_count = value


    property texture_key:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            return texture_manager.get_texkey_from_index_key(
                component_data.texkey)

        def __set__(self, str value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef unsigned int texkey = texture_manager.get_texkey_from_name(
                value)
            cdef float u0, v0, u1, v1
            cdef list uv_list = texture_manager.get_uvs(value)
            u0 = uv_list[0]
            v0 = uv_list[1]
            u1 = uv_list[2]
            v1 = uv_list[3]
            component_data.texkey = texkey
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            set_vertex_attribute = vert_mesh.set_vertex_attribute
            set_vertex_attribute(0, 2, u0)
            set_vertex_attribute(0, 3, v0)
            set_vertex_attribute(1, 2, u0)
            set_vertex_attribute(1, 3, v1)
            set_vertex_attribute(2, 2, u1)
            set_vertex_attribute(2, 3, v1)
            set_vertex_attribute(3, 2, u1)
            set_vertex_attribute(3, 3, v0)


    property render:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            return component_data.render

        def __set__(self, bool value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            if value:
                component_data.render = 1
            else:
                component_data.render = 0


    property vertex_count:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            return vert_mesh._vert_count

        def __set__(self, int value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            vert_mesh.vertex_count = value


    property index_count:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            return vert_mesh._index_count

        def __set__(self, int value):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            vert_mesh.index_count = value


    property vert_mesh:
        def __get__(self):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int vert_mesh_index = component_data.vert_index_key
            cdef list meshes = model_manager.meshes
            cdef VertMesh vert_mesh = meshes[vert_mesh_index]
            return vert_mesh

        def __set__(self, str vert_mesh_key):
            cdef RenderStruct* component_data = <RenderStruct*>self.pointer
            cdef int new_index = model_manager.get_mesh_index(vert_mesh_key)
            component_data.vert_index_key = new_index


cdef class Renderer(StaticMemGameSystem):
    '''The basic KivEnt renderer draws every entity every frame. Entities 
    will be batched into groups of up to **maximum_vertices**, if they can
    share the source of texture. The drawing will use a VertexFormat4F that 
    only accounts for position and uv coordinates. This GameSystem is only 
    dependent on its own component and the PositionComponent2D.

    **Attributes:**
        **shader_source** (StringProperty): Path to the .glsl to be used, do 
        include '.glsl' in the name. You must ensure that your shader matches 
        your vertex format or you will have problems

        **maximum_vertices** (NumericProperty): The maximum number of vertices
         that will be placed in a batch. 

        **attribute_count** (NumericProperty): The number of attributes each 
        vertex will contain. Computed automatically inside 
        calculate_vertex_format.

        **vertex_format** (dict): describes format of data sent to shaders,
        generated automatically based on do_rotate, do_scale, do_color

        **blend_factor_source** (NumericProperty): Sets the Blend Source. for
        a visual exploration of this concept visit : 
        http://www.andersriggelsen.dk/glblendfunc.php
        Options Include:
        GL_SRC_ALPHA, GL_ONE, GL_ZERO, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR, 
        GL_ONE_MINUS_SRC_ALPHA, GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA, 
        GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR

        **blend_factor_dest** (NumericProperty): Sets the Blend Dest. 
        See blend_factor_sourc for more details.

        **reset_blend_factor_source** (NumericProperty): The blend source
        will be reset to this after drawing this canvas. 
        See blend_factor_source for more details.

        **reset_blend_factor_dest** (NumericProperty): The blend dest
        will be reset to this after drawing this canvas. 
        See blend_factor_source for more details.

        **smallest_vertex_count** (NumericProperty, should be int): Used to 
        estimate the number of entities that can fit in each batch at max,
        batch ComponentPointerAggregator will then be **size_of_batches** //
        **smallest_vertex_count** * **vertex_format_size**.  

        **max_batches** (NumericProperty, should be int): The maximum number 
        of space to reserve for this renderer. Will be **max_batches** * 
        **frame_count** * **size_of_batches**.

        **size_of_batches** (NumericProperty): Size in kibibytes of each batch.

        **vertex_format_size** (NumericProperty): The size in bytes of the 
        vertex_format to be used. Will typically be the result of calling
        sizeof on the struct being used.

        **frame_count** (NumericProperty, should be int): The number of frames 
        to multibuffer. 

    **Attributes: (Cython Access Only)**

        **attribute_count** (unsigned int): The number of attributes in the 
        VertMesh format for this renderer. Defaults to 4 (x, y, u, v).

        **batch_manager** (BatchManager): The BatchManager that is responsible
        for actually submitting vertex data to the GPU.

    '''
    system_id = StringProperty('renderer')
    updateable = BooleanProperty(True)
    renderable = BooleanProperty(True)
    max_batches = NumericProperty(20)
    size_of_batches = NumericProperty(256)
    vertex_format_size = NumericProperty(sizeof(VertexFormat4F))
    frame_count = NumericProperty(2)
    smallest_vertex_count = NumericProperty(4)
    system_names = ListProperty(['renderer', 'position'])
    shader_source = StringProperty('positionshader.glsl')
    blend_factor_source = NumericProperty(GL_SRC_ALPHA)
    blend_factor_dest = NumericProperty(GL_ONE_MINUS_SRC_ALPHA)
    reset_blend_factor_source = NumericProperty(GL_SRC_ALPHA)
    reset_blend_factor_dest = NumericProperty(GL_ONE_MINUS_SRC_ALPHA)
    type_size = NumericProperty(sizeof(RenderStruct))
    component_type = ObjectProperty(RenderComponent)

    
    def __init__(self, **kwargs):
        self.canvas = RenderContext(use_parent_projection=True)
        if 'shader_source' in kwargs:
            self.canvas.shader.source = kwargs.get('shader_source')
        super(Renderer, self).__init__(**kwargs)
        self.attribute_count = 4
        with self.canvas.before:
            Callback(self._set_blend_func)
        with self.canvas.after:
            Callback(self._reset_blend_func)         

    def _set_blend_func(self, instruction):
        '''This function is called internally in a callback on canvas.before 
        to set up the blend function, it will obey **blend_factor_source**
        and **blend_factor_dest** properties.'''
        glBlendFunc(self.blend_factor_source, self.blend_factor_dest)

    def _reset_blend_func(self, instruction):
        '''This function is called internally in a callback on canvas.after
        to reset the blend function, it will obey **reset_blend_factor_source**
        and **reset_blend_factor_dest** properties.'''
        glBlendFunc(self.reset_blend_factor_source, 
            self.reset_blend_factor_dest)

    def _update(self, dt):
        '''
        We only want to update renderer once per frame, so we will override
        the basic GameSystem logic here which accounts appropriately for
        dt.
        '''
        self.update(dt)

    def on_shader_source(self, instance, value):
        '''Event that sets the canvas.shader.source property when the 
        **shader_source** property is set'''
        self.canvas.shader.source = value

    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RenderStruct* pointer = <RenderStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer.attrib_count = 0
        pointer.vert_index_key = -1
        pointer.texkey = -1
        pointer.render = 0
        pointer.batch_id = -1
        pointer.vert_index = -1
        pointer.ind_index = -1

    cdef void* setup_batch_manager(self, Buffer master_buffer) except NULL:
        '''Function called internally during **allocate** to setup the 
        BatchManager. The KEVertexFormat should be initialized in this 
        function as well.
        '''
        cdef KEVertexFormat batch_vertex_format = KEVertexFormat(
            sizeof(VertexFormat4F), *vertex_format_4f)
        self.batch_manager = BatchManager(
            self.size_of_batches, self.max_batches, self.frame_count, 
            batch_vertex_format, master_buffer, 'triangles', self.canvas,
            [x for x in self.system_names], 
            self.smallest_vertex_count, self.gameworld)
        return <void*>self.batch_manager

    def allocate(self, Buffer master_buffer, dict reserve_spec):
        super(Renderer, self).allocate(master_buffer, reserve_spec)
        self.setup_batch_manager(master_buffer)

    def get_system_size(self):
        return super(
            Renderer, self).get_system_size() + self.batch_manager.get_size()

    def get_size_estimate(self, dict reserve_spec):
        cdef unsigned int total = super(Renderer, self).get_size_estimate(
            reserve_spec)
        cdef unsigned int count = len(self.system_names)
        cdef unsigned int vsize_in_bytes = self.size_of_batches * 1024
        cdef unsigned int vtype_size = self.vertex_format_size
        cdef unsigned int vert_slots_per_block = vsize_in_bytes // vtype_size
        cdef unsigned int ent_per_batch = (
            vert_slots_per_block // self.smallest_vertex_count)

        cdef unsigned int size_per_ent = sizeof(void*) * count
        pointer_size_in_kb = (
            (self.max_batches * ent_per_batch * size_per_ent) // 1024) + 1
        return total + pointer_size_in_kb + (
            self.max_batches * self.size_of_batches * self.frame_count * 2)
        
    cdef void* _init_component(self, unsigned int component_index, 
        unsigned int entity_id, bool render, unsigned int attrib_count, 
        unsigned int vert_index_key, unsigned int texkey) except NULL:
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RenderStruct* pointer = <RenderStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = entity_id
        pointer.attrib_count = attrib_count
        pointer.vert_index_key = vert_index_key
        pointer.texkey = texkey
        if render:
            pointer.render = 1
        else:
            pointer.render = 0
        self._batch_entity(entity_id, pointer)
        return pointer
        
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone_name, args):
        cdef float w, h
        cdef int vert_index_key, texkey
        cdef bool copy, render
        cdef int attrib_count = self.attribute_count
        if 'texture' in args:
            texture_key = args['texture']
            texkey = texture_manager.get_texkey_from_name(texture_key)

        else:
            texture_key = str(None)
            texkey = -1
        if 'size' in args:
            w, h = args['size']
        if 'copy' in args:
            copy = args['copy']
        else:
            copy = False
        if 'render' in args:
            render = args['render']
        else:
            render = True
        if 'vert_mesh_key' in args:
            vert_mesh_key = args['vert_mesh_key']
            vert_index_key = model_manager.get_mesh_index(vert_mesh_key)
        else:
            vert_index_key = -1
        if vert_index_key == -1:
            mesh_key = str(attrib_count) + texture_key
            exists = model_manager.does_key_exist(mesh_key)
            if not exists:
                model_manager.load_textured_rectangle(attrib_count, 
                    w, h, texture_key, mesh_key)
            vert_index_key = model_manager.get_mesh_index(mesh_key)
        self._init_component(component_index, entity_id, render, attrib_count,
            vert_index_key, texkey)

    def update(self, dt):
        '''Update function where all drawing of entities is performed. 
        Override this method if you would like to create a renderer with 
        customized behavior. The basic logic is that we iterate through 
        each batch getting the entities in that batch, then iterate through 
        the vertices in the RenderComponent.vert_mesh, copying every 
        vertex into the batches data and combining it with data from other 
        components.
        Args:
            dt (float): The time elapsed since last update, not usually 
            used in rendering but passed in to maintain a consistent API.
        '''
        cdef IndexedBatch batch
        cdef list batches
        cdef unsigned int batch_key
        cdef unsigned int index_offset, vert_offset
        cdef RenderStruct* render_comp
        cdef PositionStruct2D* pos_comp
        cdef VertexFormat4F* frame_data
        cdef GLushort* frame_indices
        cdef VertMesh vert_mesh
        cdef float* mesh_data
        cdef VertexFormat4F* vertex
        cdef unsigned short* mesh_indices
        cdef unsigned int used, i, real_index, component_count

        cdef ComponentPointerAggregator entity_components
        cdef int attribute_count = self.attribute_count
        cdef BatchManager batch_manager = self.batch_manager
        cdef dict batch_groups = batch_manager.batch_groups
        cdef list meshes = model_manager.meshes
        cdef CMesh mesh_instruction
        cdef MemoryBlock components_block
        cdef void** component_data
    
        for batch_key in batch_groups:
            batches = batch_groups[batch_key]
            for batch in batches:
                entity_components = batch.entity_components
                components_block = entity_components.memory_block
                used = components_block.used_count
                component_count = entity_components.count
                component_data = <void**>components_block.data
                frame_data = <VertexFormat4F*>batch.get_vbo_frame_to_draw()
                frame_indices = <GLushort*>batch.get_indices_frame_to_draw()
                index_offset = 0
                for i in range(used):
                    real_index = i * component_count
                    if component_data[real_index] == NULL:
                        continue
                    render_comp = <RenderStruct*>component_data[real_index+0]
                    vert_offset = render_comp.vert_index
                    vert_mesh = meshes[render_comp.vert_index_key]
                    vertex_count = vert_mesh._vert_count
                    index_count = vert_mesh._index_count
                    if render_comp.render:
                        pos_comp = <PositionStruct2D*>component_data[
                            real_index+1]
                        mesh_data = vert_mesh._data
                        mesh_indices = vert_mesh._indices
                        for i in range(index_count):
                            frame_indices[i+index_offset] = (
                                mesh_indices[i] + vert_offset)
                        for n in range(vertex_count):
                            vertex = &frame_data[n + vert_offset]
                            vertex.pos[0] = pos_comp.x + mesh_data[
                                n*attribute_count]
                            vertex.pos[1] = pos_comp.y + mesh_data[
                                n*attribute_count+1]
                            vertex.uvs[0] = mesh_data[n*attribute_count+2]
                            vertex.uvs[1] = mesh_data[n*attribute_count+3]
                        index_offset += index_count
                batch.set_index_count_for_frame(index_offset)
                mesh_instruction = batch.mesh_instruction
                mesh_instruction.flag_update()

    def remove_component(self, unsigned int component_index):
        cdef IndexedMemoryZone components = self.imz_components
        cdef RenderStruct* pointer = <RenderStruct*>components.get_pointer(
            component_index)
        self._unbatch_entity(pointer.entity_id, pointer)
        
        super(Renderer, self).remove_component(component_index)

    def unbatch_entity(self, unsigned int entity_id):
        '''Python accessible function for unbatching the entity, the real work 
        is done in the cdefed _unbatch_entity.
        Args:
            entity_id (unsigned int): The id of the entity to unbatch.
        '''
        cdef IndexedMemoryZone components = self.imz_components
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef Entity entity = entities[entity_id]
        cdef unsigned int component_index = entity.get_component_index(
            self.system_id)
        self._unbatch_entity(entity_id, <RenderStruct*>components.get_pointer(
            component_index))

    cdef void* _unbatch_entity(self, unsigned int entity_id, 
        RenderStruct* component_data) except NULL:
        '''The actual unbatching function. Will call 
        **batch_manager**.unbatch_entity.
        Args:
            entity_id (unsigned int): The id of the entity to be unbatched.

            component_data (RenderStruct*): Pointer to the actual component 
            data for the entity.

        Return:
            void*: Will return a pointer to the component_data passed in 
            if successful, will raise an exception if NULL is returned. This 
            return is required for exception propogation.
        '''
        cdef list meshes = model_manager.meshes
        cdef VertMesh vert_mesh = meshes[component_data.vert_index_key]
        cdef unsigned int vert_count = vert_mesh._vert_count
        cdef unsigned int index_count = vert_mesh._index_count
        self.batch_manager.unbatch_entity(entity_id, component_data.batch_id,
            vert_count, index_count, component_data.vert_index,
            component_data.ind_index)
        component_data.batch_id = -1
        component_data.vert_index = -1
        component_data.ind_index = -1
        return component_data

    def batch_entity(self, unsigned int entity_id):
        '''Python accessible function for batching the entity, the real work 
        is done in the cdefed _batch_entity.
        Args:
            entity_id (unsigned int): The id of the entity to unbatch.
        '''
        cdef IndexedMemoryZone components = self.imz_components
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef Entity entity = entities[entity_id]
        cdef unsigned int component_index = entity.get_component_index(
            self.system_id)
        self._batch_entity(entity_id, <RenderStruct*>components.get_pointer(
            component_index))

    cdef void* _batch_entity(self, unsigned int entity_id, 
        RenderStruct* component_data) except NULL:
        '''The actual batching function. Will call 
        **batch_manager**.batch_entity.
        Args:
            entity_id (unsigned int): The id of the entity to be unbatched.

            component_data (RenderStruct*): Pointer to the actual component 
            data for the entity.

        Return:
            void*: Will return a pointer to the component_data passed in 
            if successful, will raise an exception if NULL is returned. This 
            return is required for exception propogation.
        '''
        cdef list meshes = model_manager.meshes
        cdef tuple batch_indices
        cdef VertMesh vert_mesh = meshes[component_data.vert_index_key]
        cdef unsigned int vert_count = vert_mesh._vert_count
        cdef unsigned int index_count = vert_mesh._index_count
        cdef int texkey = texture_manager.get_groupkey_from_texkey(
            component_data.texkey)
        batch_indices = self.batch_manager.batch_entity(entity_id,
            texkey, vert_count, index_count)
        component_data.batch_id = batch_indices[0]
        component_data.vert_index = batch_indices[1]
        component_data.ind_index = batch_indices[2]
        return component_data

cdef class PhysicsRenderer(Renderer):
    '''This renderer draws every entity every frame, with rotation data suitable
    for use with entities using the CymunkPhysics GameSystems. The drawing will 
    use a VertexFormat7F that accounts for position of vertex, uv coordinates,
    the rotation around the center and the actual center of the rotation. 
    This GameSystem is dependent on its own component, the PositionComponent2D, 
    and the RotateComponent2D.
    '''
    system_names = ListProperty(['physics_renderer', 'position',
        'rotate'])
    system_id = StringProperty('physics_renderer')
    vertex_format_size = NumericProperty(sizeof(VertexFormat7F))
    
    cdef void* setup_batch_manager(self, Buffer master_buffer) except NULL:
        cdef KEVertexFormat batch_vertex_format = KEVertexFormat(
            sizeof(VertexFormat7F), *vertex_format_7f)
        self.batch_manager = BatchManager(
            self.size_of_batches, self.max_batches, self.frame_count, 
            batch_vertex_format, master_buffer, 'triangles', self.canvas,
            self.gameworld.entities, [x for x in self.system_names], 
            self.smallest_vertex_count)
        return <void*>self.batch_manager

    def update(self, dt):
        cdef IndexedBatch batch
        cdef list batches
        cdef unsigned int batch_key
        cdef unsigned int index_offset, vert_offset
        cdef RenderStruct* render_comp
        cdef PositionStruct2D* pos_comp
        cdef RotateStruct2D* rot_comp
        cdef VertexFormat7F* frame_data
        cdef GLushort* frame_indices
        cdef VertMesh vert_mesh
        cdef float* mesh_data
        cdef VertexFormat7F* vertex
        cdef unsigned short* mesh_indices
        cdef unsigned int used, i, real_index, component_count, x, y

        cdef ComponentPointerAggregator entity_components
        cdef int attribute_count = self.attribute_count
        cdef BatchManager batch_manager = self.batch_manager
        cdef dict batch_groups = batch_manager.batch_groups
        cdef list meshes = model_manager.meshes
        cdef CMesh mesh_instruction
        cdef MemoryBlock components_block
        cdef void** component_data
        cdef bool exists = True
        for batch_key in batch_groups:
            batches = batch_groups[batch_key]
            for batch in batches:
                entity_components = batch.entity_components
                components_block = entity_components.memory_block
                used = components_block.used_count
                component_count = entity_components.count
                component_data = <void**>components_block.data
                frame_data = <VertexFormat7F*>batch.get_vbo_frame_to_draw()
                frame_indices = <GLushort*>batch.get_indices_frame_to_draw()
                index_offset = 0
                for i in range(components_block.size):
                    real_index = i * component_count
                    if component_data[real_index] == NULL:
                        continue
                    render_comp = <RenderStruct*>component_data[real_index+0]
                    vert_offset = render_comp.vert_index
                    vert_mesh = meshes[render_comp.vert_index_key]
                    vertex_count = vert_mesh._vert_count
                    index_count = vert_mesh._index_count
                    if render_comp.render:
                        pos_comp = <PositionStruct2D*>component_data[
                            real_index+1]
                        mesh_data = vert_mesh._data
                        rot_comp = <RotateStruct2D*>component_data[real_index+2]
                        mesh_indices = vert_mesh._indices
                        for y in range(index_count):
                            frame_indices[y+index_offset] = (
                                mesh_indices[y] + vert_offset)
                        for n in range(vertex_count):
                            vertex = &frame_data[n + vert_offset]
                            vertex.pos[0] = mesh_data[n*attribute_count]
                            vertex.pos[1] = mesh_data[n*attribute_count+1]
                            vertex.uvs[0] = mesh_data[n*attribute_count+2]
                            vertex.uvs[1] = mesh_data[n*attribute_count+3]
                            vertex.rot = rot_comp.r
                            vertex.center[0] = pos_comp.x
                            vertex.center[1] = pos_comp.y
                        index_offset += index_count
                batch.set_index_count_for_frame(index_offset)
                mesh_instruction = batch.mesh_instruction
                mesh_instruction.flag_update()


Factory.register('Renderer', cls=Renderer)
Factory.register('PhysicsRenderer', cls=PhysicsRenderer)