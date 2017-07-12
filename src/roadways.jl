const _ROADWAY_TYPES = Union{Curve,Straight1DRoadway,Wraparound{Straight1DRoadway},Wraparound{Curve},Roadway}
Base.show(io::IO, ::MIME"image/png", roadway::_ROADWAY_TYPES) = show(io, MIME"image/png"(), render(roadway))
function render(roadway::_ROADWAY_TYPES;
    canvas_width::Int=DEFAULT_CANVAS_WIDTH,
    canvas_height::Int=DEFAULT_CANVAS_HEIGHT,
    rendermodel = RenderModel(),
    cam::Camera = FitToContentCamera(),
    )

    s = CairoRGBSurface(canvas_width, canvas_height)
    ctx = creategc(s)
    clear_setup!(rendermodel)

    render!(rendermodel, roadway)

    camera_set!(rendermodel, cam, canvas_width, canvas_height)
    render(rendermodel, ctx, canvas_width, canvas_height)
    return s
end

render!(rendermodel::RenderModel, roadway::Void) = rendermodel

function render!(
    rendermodel::RenderModel,
    boundary::LaneBoundary,
    pts::Matrix{Float64},
    lane_marking_width  :: Real=0.15, # [m]
    lane_dash_len       :: Real=0.91, # [m]
    lane_dash_spacing   :: Real=2.74, # [m]
    lane_dash_offset    :: Real=0.00  # [m]
    )

    marker_color = boundary.color == :yellow ? COLOR_LANE_MARKINGS_YELLOW : COLOR_LANE_MARKINGS_WHITE
    if boundary.style == :broken
        add_instruction!(rendermodel, render_dashed_line, (pts, marker_color, lane_marking_width, lane_dash_len, lane_dash_spacing, lane_dash_offset))
    else
        add_instruction!(rendermodel, render_line, (pts, marker_color, lane_marking_width))
    end
    return rendermodel
end

function render_asphalt!(rendermodel::RenderModel, curve::Curve;
    color::Colorant=COLOR_ASPHALT,
    width::Float64=DEFAULT_LANE_WIDTH,
    )

    n = length(curve)
    pts = Array{Float64}(2, n)
    for (i,pt) in enumerate(lane.curve)
        pts[1,i] = pt.pos.x
        pts[2,i] = pt.pos.y
    end

    add_instruction!(rendermodel, render_line, (pts, color, width))
    return rendermodel
end
function render_lanemarking_left!(rendermodel::RenderModel, curve::Curve;
    boundary::LaneBoundary=LaneBoundary(:solid, :white),
    width::Float64=DEFAULT_LANE_WIDTH,
    )

    n = length(curve)
    pts_left = Array{Float64}(2, n)
    for (i,pt) in enumerate(curve)
        p_left = pt.pos + polar(width/2, pt.pos.θ + π/2)

        pts_left[1,i] = p_left.x
        pts_left[2,i] = p_left.y
    end

    render!(rendermodel, lane.boundary_left, pts_left)
    return rendermodel
end
function render_lanemarking_right!(rendermodel::RenderModel, curve::Curve;
    boundary::LaneBoundary=LaneBoundary(:solid, :white),
    width::Float64=DEFAULT_LANE_WIDTH,
    )

    n = length(curve)
    pts_right = Array{Float64}(2, n)
    for (i,pt) in enumerate(curve)
        p_right = pt.pos - polar(width/2, pt.pos.θ + π/2)

        pts_right[1,i] = p_right.x
        pts_right[2,i] = p_right.y
    end
    render!(rendermodel, lane.boundary_right, pts_right)

    return rendermodel
end
function render!(rendermodel::RenderModel, curve::Curve;
    color_asphalt::Colorant=COLOR_ASPHALT,
    lane_width::Float64=DEFAULT_LANE_WIDTH,
    boundary_left::LaneBoundary=LaneBoundary(:solid, :white),
    boundary_right::LaneBoundary=LaneBoundary(:solid, :white),
    )

    render_asphalt!(rendermodel, curve, roadway, color=color_asphalt, width=lane_width)
    render_lanemarking_left!(rendermodel, curve, roadway, boundary=boundary_left, width=lane_width)
    render_lanemarking_right!(rendermodel, curve, roadway, boundary=boundary_right, width=lane_width)
    return rendermodel
end

function render!(rendermodel::RenderModel, roadway::Straight1DRoadway;
    color_asphalt::Colorant=COLOR_ASPHALT,
    lane_width::Float64 = DEFAULT_LANE_WIDTH,
    extra_length::Float64 = 0.0, # [m]
    lane_marking_width::Float64 = 0.15, # [m]
    )

    pts = Array{VecE2}(2)
    pts[1] = VecE2(-extra_length, 0)
    pts[2] = VecE2( extra_length + roadway.len, 0)

    add_instruction!(rendermodel, render_line, (pts, color_asphalt, lane_width))
    add_instruction!(rendermodel, render_line, ([p + VecE2(0, -lane_width/2) for p in pts], COLOR_LANE_MARKINGS_WHITE, lane_marking_width))
    add_instruction!(rendermodel, render_line, ([p + VecE2(0,  lane_width/2) for p in pts], COLOR_LANE_MARKINGS_WHITE, lane_marking_width))
    return rendermodel
end

render!(rendermodel::RenderModel, roadway::Wraparound; kwargs...) = render!(rendermodel, roadway.road; kwargs..., extra_length=50.0)

function render!(rendermodel::RenderModel, lane::Lane, roadway::Roadway;
    color_asphalt       :: Colorant=COLOR_ASPHALT,
    )

    n = length(lane.curve)
    pts = Array{Float64}(2, n + has_next(lane))
    for (i,pt) in enumerate(lane.curve)
        pts[1,i] = pt.pos.x
        pts[2,i] = pt.pos.y
    end
    if has_next(lane)
        pt = next_lane_point(lane, roadway)
        pts[1,end] = pt.pos.x
        pts[2,end] = pt.pos.y
    end

    add_instruction!(rendermodel, render_line, (pts, color_asphalt, lane.width))
    return rendermodel
end
function render!(rendermodel::RenderModel, roadway::Roadway;
    color_asphalt       :: Colorant=COLOR_ASPHALT,
    lane_marking_width  :: Real=0.15, # [m]
    lane_dash_len       :: Real=0.91, # [m]
    lane_dash_spacing   :: Real=2.74, # [m]
    lane_dash_offset    :: Real=0.00  # [m]
    )

    # render the asphalt between the leftmost and rightmost lane markers
    for seg in roadway.segments
        if !isempty(seg.lanes)
            laneR = seg.lanes[1]
            laneL = seg.lanes[end]

            pts = Array{Float64}(2, length(laneL.curve) + has_next(laneL) +
                                        length(laneR.curve) + has_next(laneR) +
                                        2*length(seg.lanes))
            pts_index = 0
            for pt in laneL.curve
                edgept = pt.pos + polar(laneL.width/2, pt.pos.θ + π/2)
                pts_index += 1
                pts[1, pts_index] = edgept.x
                pts[2, pts_index] = edgept.y
            end
            if has_next(laneL)
                pt = next_lane_point(laneL, roadway)
                edgept = pt.pos + polar(laneL.width/2, pt.pos.θ + π/2)
                pts_index += 1
                pts[1, pts_index] = edgept.x
                pts[2, pts_index] = edgept.y
            end
            for i in reverse(1:length(seg.lanes))
                lane = seg.lanes[i]
                if has_next(lane)
                    pt = next_lane_point(lane, roadway).pos
                else
                    pt = lane.curve[end].pos
                end
                pts_index += 1
                pts[1, pts_index] = pt.x
                pts[2, pts_index] = pt.y
            end

            if has_next(laneR)
                pt = next_lane_point(laneR, roadway)
                edgept = pt.pos + polar(laneR.width/2, pt.pos.θ - π/2)
                pts_index += 1
                pts[1, pts_index] = edgept.x
                pts[2, pts_index] = edgept.y
            end
            for j in length(laneR.curve) : -1 : 1
                pt = laneR.curve[j]
                edgept = pt.pos + polar(laneR.width/2, pt.pos.θ - π/2)
                pts_index += 1
                pts[1, pts_index] = edgept.x
                pts[2, pts_index] = edgept.y
            end
            for i in 1:length(seg.lanes)
                lane = seg.lanes[i]
                pt = lane.curve[1].pos
                pts_index += 1
                pts[1, pts_index] = pt.x
                pts[2, pts_index] = pt.y
            end

            add_instruction!(rendermodel, render_fill_region, (pts, color_asphalt))
        end
        # for lane in seg.lanes
        #     render!(rendermodel, lane, roadway)
        # end
    end

    # render the lane edges
    for seg in roadway.segments
        for lane in seg.lanes

            N = length(lane.curve)
            halfwidth = lane.width/2

            # always render the left lane marking
            pts_left = Array{Float64}(2, N)
            for (i,pt) in enumerate(lane.curve)
                p_left = pt.pos + polar(halfwidth, pt.pos.θ + π/2)

                pts_left[1,i] = p_left.x
                pts_left[2,i] = p_left.y
            end
            if has_next(lane)
                lane2 = next_lane(lane, roadway)
                pt = lane2.curve[1]
                p_left = pt.pos + polar(lane2.width/2, pt.pos.θ + π/2)
                pts_left = hcat(pts_left, [p_left.x, p_left.y])
            end

            render!(rendermodel, lane.boundary_left, pts_left, lane_marking_width, lane_dash_len, lane_dash_spacing, lane_dash_offset)

            # only render the right lane marking if this is the first lane
            if lane.tag.lane == 1
                pts_right = Array{Float64}(2, N)

                for (i,pt) in enumerate(lane.curve)
                    p_right = pt.pos - polar(halfwidth, pt.pos.θ + π/2)

                    pts_right[1,i] = p_right.x
                    pts_right[2,i] = p_right.y
                end

                if has_next(lane)
                    lane2 = next_lane(lane, roadway)
                    pt = lane2.curve[1]
                    p_right = pt.pos - polar(lane2.width/2, pt.pos.θ + π/2)
                    pts_right = hcat(pts_right, [p_right.x, p_right.y])
                end

                render!(rendermodel, lane.boundary_right, pts_right, lane_marking_width, lane_dash_len, lane_dash_spacing, lane_dash_offset)
            end
        end
    end

    return rendermodel
end

